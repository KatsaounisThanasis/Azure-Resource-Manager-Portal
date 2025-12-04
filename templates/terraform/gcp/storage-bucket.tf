# GCP Cloud Storage Bucket - Equivalent to Azure Storage Account
# This template creates a Cloud Storage bucket with versioning

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "bucket_name" {
  type        = string
  description = "Name of the GCS bucket (must be globally unique)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_\\.]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must consist of lowercase letters, numbers, hyphens, underscores, and dots"
  }
}

variable "location" {
  type        = string
  description = "GCS bucket location for resource deployment"
  default = "US"
}

variable "storage_class" {
  type        = string
  description = "Storage class - affects cost and access patterns (STANDARD=frequent access, NEARLINE=monthly access, COLDLINE=quarterly access, ARCHIVE=yearly access)"

  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Invalid storage class"
  }
}

variable "enable_versioning" {
  type        = bool
  description = "Enable object versioning"
  default     = true
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to the bucket"
  default = {
    managed-by  = "terraform"
    environment = "production"
  }
}

# Cloud Storage Bucket
resource "google_storage_bucket" "main" {
  name          = var.bucket_name
  location      = var.location
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = var.enable_versioning
  }

  # Encryption: Uses Google-managed encryption by default when not specified

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = var.labels
}

# Bucket IAM - Block public access by default
resource "google_storage_bucket_iam_binding" "prevent_public" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectViewer"

  members = []  # Empty members = no public access
}

# Outputs
output "bucket_name" {
  description = "Name of the bucket"
  value       = google_storage_bucket.main.name
}

output "bucket_url" {
  description = "URL of the bucket"
  value       = google_storage_bucket.main.url
}

output "bucket_self_link" {
  description = "Self link of the bucket"
  value       = google_storage_bucket.main.self_link
}
