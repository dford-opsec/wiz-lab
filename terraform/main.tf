# ==============================================================================
# 0. PROVIDER CONFIGURATION
# ==============================================================================
provider "google" {
  project = var.project_id
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

# Public Subnet for MongoDB VM
resource "google_compute_subnetwork" "public_subnet" {
  name          = "wiz-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.wiz_vpc.id
  private_ip_google_access = true # Fixes CKV_GCP_74

  # Fixes CKV_GCP_26
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private Subnet for GKE Cluster
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "wiz-private-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.wiz_vpc.id
  private_ip_google_access = true

  # Fixes CKV_GCP_26
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router & NAT (Required for Private GKE Nodes to pull internet images)
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

# Overly Permissive Service Account (Compute Admin)
resource "google_service_account" "vulnerable_sa" {
  account_id   = "mongodb-vulnerable-sa"
  display_name = "Vulnerable Service Account for MongoDB VM"
}

resource "google_project_iam_member" "vulnerable_sa_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.vulnerable_sa.email}"
}

# Publicly Readable Cloud Storage Bucket for Backups
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "db_backups" {
  name          = "wiz-db-backups-${var.project_id}-${random_id.bucket_suffix.hex}"
  location      = "US"
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# ==============================================================================
# 3. FIREWALL RULES
# ==============================================================================

# SSH exposed to the public internet
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

# Restrict MongoDB access to the GKE private subnet only
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
      image = "ubuntu-os-cloud/ubuntu-1804-lts" # 1+ year outdated Linux OS
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.wiz_vpc.name
    subnetwork = google_compute_subnetwork.public_subnet.name
    access_config {} # Grants Public IP
  }

  service_account {
    email  = google_service_account.vulnerable_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    # Install MongoDB 4.4
    wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29

    # Configure auth and bind IP
    sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    echo -e "security:\n  authorization: enabled" | sudo tee -a /etc/mongod.conf

    sudo systemctl enable mongod
    sudo systemctl start mongod
    sleep 10

    # Create admin user
    mongo admin --eval 'db.createUser({user: "admin", pwd: "Password123!", roles: [{role: "userAdminAnyDatabase", db: "admin"}, "readWriteAnyDatabase"]})'

    # Create backup script
    cat << 'EOF' > /usr/local/bin/backup_mongo.sh
    #!/bin/bash
    TIMESTAMP=$(date +"%F")
    BACKUP_DIR="/tmp/mongodump-$TIMESTAMP"
    mongodump --username admin --password Password123! --authenticationDatabase admin --out $BACKUP_DIR
    gsutil cp -r $BACKUP_DIR gs://${google_storage_bucket.db_backups.name}/
    rm -rf $BACKUP_DIR
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
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "wiz-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.wiz_cluster.name
  node_count = 1

  # Fixes CKV_GCP_9 and CKV_GCP_10
  management {
    auto_repair  = true 
    auto_upgrade = true 
  }

  node_config {
    machine_type = "e2-medium"
    spot         = true
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]
  }
}

# ==============================================================================
# 6. CLOUD NATIVE SECURITY TOOLS
# ==============================================================================

# Audit Logging (Control Plane)
resource "google_project_iam_audit_config" "gcs_audit_logs" {
  project = var.project_id
  service = "storage.googleapis.com"
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
  audit_log_config { log_type = "ADMIN_READ" }
}

# Preventative Control: Block Service Account Key Creation
resource "google_project_organization_policy" "disable_sa_keys" {
  project    = var.project_id
  constraint = "iam.disableServiceAccountKeyCreation"
  boolean_policy {
    enforced = true
  }
}

# Detective Control: Log-based metric & alert for SSH access to Mongo VM
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

resource "google_monitoring_alert_policy" "ssh_alert" {
  display_name = "Alert: SSH Access to MongoDB VM Detected"
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
