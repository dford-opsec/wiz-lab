# 1. The Serverless Identity (The Attack Vector)
resource "google_service_account" "attack_sa" {
  account_id   = "wiz-attack-simulation-sa"
  display_name = "Attack Simulation Cloud Run Identity"
}

# Grant it permission to authenticate to GKE
resource "google_project_iam_member" "attack_sa_gke" {
  project = "clgcporg10-181"
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.attack_sa.email}"
}

# Grant it Compute Admin so the ssh-attack.sh works
resource "google_project_iam_member" "attack_sa_compute" {
  project = "clgcporg10-181"
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.attack_sa.email}"
}

# 2. The Cloud Run Job
resource "google_cloud_run_v2_job" "attack_simulation" {
  name     = "wiz-attack-simulation-job"
  location = "us-central1"

  template {
    template {
      service_account = google_service_account.attack_sa.email
      containers {
        # This assumes you push the image built in GitHub Actions to Artifact Registry
        image = "us-central1-docker.pkg.dev/clgcporg10-181/my-repo/attack-sim:latest"
      }
    }
  }
}

# 3. The Cloud Scheduler (Cron Job)
resource "google_cloud_scheduler_job" "attack_trigger" {
  name             = "trigger-attack-simulation"
  description      = "Fires the Cloud Run Job 4 times a day"
  schedule         = "0 0,6,12,18 * * *"
  time_zone        = "UTC"
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "https://us-central1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/<YOUR_PROJECT_ID>/jobs/wiz-attack-simulation-job:run"
    
    oauth_token {
      service_account_email = google_service_account.attack_sa.email
    }
  }
}
