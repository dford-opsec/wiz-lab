# ==============================================================================
# 0. PROVIDER CONFIGURATION
# ==============================================================================
provider "google" {
  project = trimspace(var.project_id)
  region  = var.region
  zone    = var.zone
}

# ==============================================================================
# 1. NETWORKING (VPC, Subnets, Cloud NAT)
# ==============================================================================
resource "google_compute_network" "wiz_vpc" {
  name                    = "wiz-exercise-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public_subnet" {
  name                     = "wiz-public-subnet"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.region
  network                  = google_compute_network.wiz_vpc.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = "wiz-private-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.wiz_vpc.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "router" {
  name    = "wiz-router"
  region  = var.region
  network = google_compute_network.wiz_vpc.name
}

resource "google_compute_router_nat" "nat" {
  name                               = "wiz-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ==============================================================================
# 2. INTENTIONALLY VULNERABLE CONFIGURATIONS (Wiz Exercise Requirements)
# ==============================================================================
resource "google_service_account" "vulnerable_sa" {
  account_id   = "mongodb-vulnerable-sa"
  display_name = "Vulnerable Service Account for MongoDB VM"
}

resource "google_project_iam_member" "vulnerable_sa_compute_admin" {
  project = trimspace(var.project_id)
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.vulnerable_sa.email}"
}

resource "google_project_iam_member" "vulnerable_sa_compute_admin" {
  project = trimspace(var.project_id)
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.vulnerable_sa.email}"
}

resource "google_project_iam_member" "vulnerable_sa_compute_admin" {
  project = trimspace(var.project_id)
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.vulnerable_sa.email}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "db_backups" {
  name          = "wiz-db-backups-${var.project_id}-${random_id.bucket_suffix.hex}"
  location      = "US"
  force_destroy = true
  labels = {
    environment = "production"
    app         = "mongodb"
    managed_by  = "terraform"
    team        = "security-eng"
  }
  # Automatically delete backups older than 7 days
  lifecycle_rule {
    condition {
      age = 7 # Days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }
  logging {
    log_bucket = "wiz-db-backups-${var.project_id}-${random_id.bucket_suffix.hex}"
  }
}
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
# Grant the VM Service Account permission to upload to the backup bucket
resource "google_storage_bucket_iam_member" "vm_backup_upload" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.vulnerable_sa.email}"
}

# ==============================================================================
# 3. FIREWALL RULES
# ==============================================================================
resource "google_compute_firewall" "allow_ssh_public" {
  name    = "allow-ssh-public"
  network = google_compute_network.wiz_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb-vm"]
}

resource "google_compute_firewall" "allow_mongodb_from_gke" {
  name    = "allow-mongodb-from-gke"
  network = google_compute_network.wiz_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
  source_ranges = [google_compute_subnetwork.private_subnet.ip_cidr_range]
  target_tags   = ["mongodb-vm"]
}

# NEW: Required for Private GKE Cluster Creation
resource "google_compute_firewall" "allow_gke_master_to_nodes" {
  name    = "allow-gke-master-to-nodes"
  network = google_compute_network.wiz_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }

  # This matches the master_ipv4_cidr_block in your google_container_cluster resource
  source_ranges = ["172.16.0.0/28"] 
}

# ==============================================================================
# 4. COMPUTE ENGINE: VULNERABLE MONGODB VM
# ==============================================================================
resource "google_compute_instance" "mongodb_vm" {
  name         = "wiz-mongodb-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["mongodb-vm"]

  boot_disk {
    initialize_params {
      image = "debian-11-bullseye-v20240110"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.wiz_vpc.name
    subnetwork = google_compute_subnetwork.public_subnet.name
    access_config {}
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    block-project-ssh-keys = "true"
  }

  service_account {
    email  = google_service_account.vulnerable_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    
    # 1. Fix the broken Debian backports repo so apt-get update works
    sudo sed -i '/bullseye-backports/ s/^/#/' /etc/apt/sources.list

    # 2. Add the MongoDB 4.4 repo (Using 'buster' because 4.4 pre-dates 'bullseye')
    wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -
    echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/4.4 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
    
    # 3. Update and Install specific vulnerable versions
    sudo apt-get update
    sudo apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29
    
    # 4. Configure network and security
    sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    echo -e "security:\n  authorization: enabled" | sudo tee -a /etc/mongod.conf
    
    # 5. Start the service
    sudo systemctl enable mongod
    sudo systemctl start mongod
    sleep 10
    
    # 6. Create Admin User
    mongo admin --eval 'db.createUser({user: "admin", pwd: "Password123!", roles: [{role: "userAdminAnyDatabase", db: "admin"}, "readWriteAnyDatabase"]})'
    
    # 7. Setup automated backups
    cat << 'EOF' > /usr/local/bin/backup_mongo.sh
    #!/bin/bash

# 1. Dynamically find the bucket name using the label
# This replaces the hardcoded "gs://wiz-db-backups-..." string
BUCKET_NAME=$(gcloud storage buckets list --filter="labels.app=mongodb" --format="value(name)" | head -n 1)

# Safety check: Exit if the bucket isn't found
if [ -z "$BUCKET_NAME" ]; then
    echo "Error: Bucket with label 'app=mongodb' not found."
    exit 1
fi

TIMESTAMP=$(date +"%F")
BACKUP_DIR="/tmp/mongodump-$TIMESTAMP"
ARCHIVE_FILE="/tmp/mongodb-backup-$TIMESTAMP.tar.gz"

# 2. Perform the dump
mongodump --username admin --password 'Password123!' --authenticationDatabase admin --db go-mongodb --out $BACKUP_DIR

# 3. Compress it (much better for GCS)
tar -czvf $ARCHIVE_FILE -C $BACKUP_DIR .

# 4. Copy the single archive file using the dynamic bucket name
gsutil cp $ARCHIVE_FILE "gs://$BUCKET_NAME/"

# 5. Cleanup
rm -rf $BACKUP_DIR $ARCHIVE_FILE
    EOF
    chmod +x /usr/local/bin/backup_mongo.sh
    echo "0 2 * * * root /usr/local/bin/backup_mongo.sh" | sudo tee /etc/cron.d/mongo_backup
  EOT
}

# ==============================================================================
# 5. KUBERNETES ENGINE: PRIVATE GKE CLUSTER
# ==============================================================================
resource "google_container_cluster" "wiz_cluster" {
  name                     = "wiz-private-cluster"
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = google_compute_network.wiz_vpc.name
  subnetwork               = google_compute_subnetwork.private_subnet.name
  deletion_protection      = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  } # Closing private_cluster_config

  network_policy {
    enabled = true
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/14"
    services_ipv4_cidr_block = "/20"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }
} # Closing google_container_cluster

resource "google_container_node_pool" "primary_nodes" {
  name       = "wiz-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.wiz_cluster.name
  node_count = 1

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-medium"
    spot         = true

    shielded_instance_config {
      enable_secure_boot = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# ==============================================================================
# 6. CLOUD NATIVE SECURITY TOOLS
# ==============================================================================
resource "google_project_iam_audit_config" "gcs_audit_logs" {
  project = trimspace(var.project_id)
  service = "storage.googleapis.com"
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
  audit_log_config { log_type = "ADMIN_READ" }
}

#resource "google_project_organization_policy" "disable_sa_keys" {
 # project    = trimspace(var.project_id)
  # constraint = "iam.disableServiceAccountKeyCreation"
  # boolean_policy {
   # enforced = true
  # }
#}

resource "google_logging_metric" "ssh_login_metric" {
  name        = "mongo_vm_ssh_logins"
  description = "Detects SSH logins to the vulnerable MongoDB VM"
  filter      = <<-EOT
    resource.type="gce_instance"
    resource.labels.instance_id="${google_compute_instance.mongodb_vm.instance_id}"
    log_name="projects/${var.project_id}/logs/auth.log"
    jsonPayload.message:"Accepted publickey" OR jsonPayload.message:"Accepted password"
  EOT
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# ------------------------------------------------------------------------------
# Forces Terraform to wait 60 seconds for the metric to propagate in GCP
# ------------------------------------------------------------------------------
resource "time_sleep" "wait_for_metric" {
  depends_on = [google_logging_metric.ssh_login_metric]

  create_duration = "60s"
}

resource "google_monitoring_alert_policy" "ssh_alert" {
  display_name = "Alert: SSH Access to MongoDB VM Detected"
  
  # NEW: Tell the alert it MUST wait for the timer to finish
  depends_on   = [time_sleep.wait_for_metric] 

  combiner     = "OR"
  conditions {
    display_name = "SSH Login Spike"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.ssh_login_metric.name}\" resource.type=\"gce_instance\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_COUNT"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
}
