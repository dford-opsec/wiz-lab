output "mongodb_internal_ip" {
  description = "The internal IP of the MongoDB VM. Put this in your K8s deployment YAML!"
  value       = google_compute_instance.mongodb_vm.network_interface.0.network_ip
}

output "mongodb_public_ip" {
  description = "The public IP of the MongoDB VM (for SSH access)"
  value       = google_compute_instance.mongodb_vm.network_interface.0.access_config.0.nat_ip
}

output "storage_bucket_name" {
  description = "The name of the publicly readable backup bucket"
  value       = google_storage_bucket.db_backups.name
}

output "gke_cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.wiz_cluster.name
}
