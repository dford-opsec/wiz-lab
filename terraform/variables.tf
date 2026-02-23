variable "project_id" {
  description = "The Google Cloud Project ID provided by CloudLabs"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy resources in (used for cost-saving zonal cluster)"
  type        = string
  default     = "us-central1-a"
}
