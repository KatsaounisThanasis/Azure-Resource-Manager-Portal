# =========================================
# Google Cloud Run - Terraform Template
# =========================================
# This template creates a Cloud Run service with:
# - Container deployment from GCR/Artifact Registry
# - Auto-scaling configuration
# - Traffic splitting
# - Custom domains and SSL certificates
# - VPC connector for private networking
# - Environment variables and secrets
# - IAM permissions and authentication
#
# Version: 1.0
# Last Updated: 2025-11-15
# =========================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# =========================================
# VARIABLES
# =========================================

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.service_name))
    error_message = "Service name must start with lowercase letter, be 1-63 characters, contain only lowercase letters, numbers, and hyphens"
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "GCP region for resource deployment"
  type        = string
  default = "US"
}

variable "image" {
  description = "Container image URL (e.g., gcr.io/project/image:tag)"
  type        = string
}

variable "container_port" {
  description = "Port on which the container listens"
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535"
  }
}

variable "cpu" {
  description = "CPU allocation for each container instance - affects cost and performance (e.g., '1000m'=1 vCPU, '2'=2 vCPUs)"
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory allocation for each container instance - affects cost and performance (e.g., '512Mi', '2Gi')"
  type        = string
  default     = "512Mi"
}

variable "max_instances" {
  description = "Maximum number of container instances (1-1000)"
  type        = number
  default     = 100

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000"
  }
}

variable "min_instances" {
  description = "Minimum number of container instances (0-1000)"
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000"
  }
}

variable "max_instance_request_concurrency" {
  description = "Maximum concurrent requests per instance (1-1000)"
  type        = number
  default     = 80

  validation {
    condition     = var.max_instance_request_concurrency >= 1 && var.max_instance_request_concurrency <= 1000
    error_message = "Max concurrency must be between 1 and 1000"
  }
}

variable "timeout_seconds" {
  description = "Request timeout in seconds (1-3600)"
  type        = number
  default     = 300

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds"
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the service"
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "Service account email for the Cloud Run service (uses default if not specified)"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables from Secret Manager"
  type = list(object({
    name        = string
    secret_name = string
    version     = string
  }))
  default = []
}

variable "vpc_connector_name" {
  description = "VPC connector name for private networking (optional)"
  type        = string
  default     = null
}

variable "vpc_egress" {
  description = "VPC egress setting (all-traffic, private-ranges-only)"
  type        = string
  default     = "private-ranges-only"

  validation {
    condition     = contains(["all-traffic", "private-ranges-only"], var.vpc_egress)
    error_message = "VPC egress must be all-traffic or private-ranges-only"
  }
}

variable "cloudsql_instances" {
  description = "List of Cloud SQL instance connection names"
  type        = list(string)
  default     = []
}

variable "ingress" {
  description = "Ingress settings (all, internal, internal-and-cloud-load-balancing)"
  type        = string
  default     = "all"

  validation {
    condition     = contains(["all", "internal", "internal-and-cloud-load-balancing"], var.ingress)
    error_message = "Ingress must be all, internal, or internal-and-cloud-load-balancing"
  }
}

variable "traffic_split" {
  description = "Traffic split configuration for revisions"
  type = list(object({
    revision_name = optional(string)
    percent       = number
    latest        = optional(bool, false)
    tag           = optional(string)
  }))
  default = [
    {
      percent = 100
      latest  = true
    }
  ]
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

# =========================================
# LOCAL VARIABLES
# =========================================

locals {
  # Common labels
  common_labels = merge(
    var.labels,
    {
      managed_by = "terraform"
      template   = "cloud-run"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Cloud Run Service
resource "google_cloud_run_v2_service" "main" {
  name     = var.service_name
  project  = var.project_id
  location = var.location
  ingress  = var.ingress
  labels   = local.common_labels

  template {
    service_account = var.service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    max_instance_request_concurrency = var.max_instance_request_concurrency

    timeout = "${var.timeout_seconds}s"

    dynamic "vpc_access" {
      for_each = var.vpc_connector_name != null ? [1] : []
      content {
        connector = var.vpc_connector_name
        egress    = var.vpc_egress
      }
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.value.name
          value_source {
            secret_key_ref {
              secret  = env.value.secret_name
              version = env.value.version
            }
          }
        }
      }
    }

    dynamic "volumes" {
      for_each = length(var.cloudsql_instances) > 0 ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = var.cloudsql_instances
        }
      }
    }
  }

  dynamic "traffic" {
    for_each = var.traffic_split
    content {
      type     = traffic.value.latest ? "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST" : "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      revision = traffic.value.latest ? null : traffic.value.revision_name
      percent  = traffic.value.percent
      tag      = traffic.value.tag
    }
  }
}

# IAM Policy for unauthenticated access
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.location
  service  = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =========================================
# OUTPUTS
# =========================================

output "service_id" {
  description = "ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.main.id
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.main.name
}

output "service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.main.uri
}

output "service_status" {
  description = "Status of the Cloud Run service"
  value = {
    url        = google_cloud_run_v2_service.main.uri
    generation = google_cloud_run_v2_service.main.generation
  }
}

output "latest_revision" {
  description = "Latest revision name"
  value       = google_cloud_run_v2_service.main.latest_ready_revision
}
