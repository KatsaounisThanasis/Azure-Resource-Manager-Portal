# =========================================
# Google Cloud SQL - Terraform Template
# =========================================
# This template creates a Cloud SQL instance with:
# - MySQL or PostgreSQL support
# - High availability configuration
# - Automated backups
# - Private IP configuration
# - Databases and users
# - Firewall rules
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

variable "instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}$", var.instance_name))
    error_message = "Instance name must start with lowercase letter, be 1-98 characters, contain only lowercase letters, numbers, and hyphens"
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
  default = "us-central1"
}

variable "database_version" {
  description = "Database version - affects features and compatibility (MYSQL_5_7, MYSQL_8_0, POSTGRES_12-15)"
  type        = string

  validation {
    condition = contains([
      "MYSQL_5_7", "MYSQL_8_0",
      "POSTGRES_12", "POSTGRES_13", "POSTGRES_14", "POSTGRES_15"
    ], var.database_version)
    error_message = "Invalid database version"
  }
}

variable "tier" {
  description = "Machine type tier - affects cost and performance (db-f1-micro=shared CPU/low cost, db-g1-small=1 vCPU shared, db-n1-standard-1+=dedicated vCPUs)"
  type        = string
  default     = "db-f1-micro"
}

variable "disk_size" {
  description = "Disk size in GB (10-65536)"
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size >= 10 && var.disk_size <= 65536
    error_message = "Disk size must be between 10 and 65536 GB"
  }
}

variable "disk_type" {
  description = "Disk type - affects cost and performance (PD_SSD=faster and more expensive, PD_HDD=slower and cheaper)"
  type        = string

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "Disk type must be PD_SSD or PD_HDD"
  }
}

variable "disk_autoresize" {
  description = "Enable automatic storage increase"
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum size for automatic storage increase in GB (0 = no limit)"
  type        = number
  default     = 0
}

variable "availability_type" {
  description = "Availability type - affects cost and redundancy (ZONAL=single zone/lower cost, REGIONAL=high availability with automatic failover)"
  type        = string

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "Availability type must be ZONAL or REGIONAL"
  }
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Backup start time in HH:MM format"
  type        = string
  default     = "03:00"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups (1-365)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365"
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery (requires backups)"
  type        = bool
  default     = false
}

variable "ipv4_enabled" {
  description = "Enable public IPv4 address"
  type        = bool
  default     = true
}

variable "require_ssl" {
  description = "Require SSL for connections"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks (CIDR ranges)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "enable_private_ip" {
  description = "Enable private IP (VPC peering required)"
  type        = bool
  default     = false
}

variable "private_network" {
  description = "VPC network for private IP (required if enable_private_ip is true)"
  type        = string
  default     = null
}

variable "database_flags" {
  description = "Database flags configuration"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "databases" {
  description = "List of databases to create"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "users" {
  description = "List of database users to create"
  type = list(object({
    name     = string
    password = string
    host     = optional(string, "%")
  }))
  default   = []
  sensitive = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
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
      template   = "cloud-sql"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Cloud SQL Instance
resource "google_sql_database_instance" "main" {
  name                = var.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size
    disk_type         = var.disk_type
    disk_autoresize   = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_enabled ? var.backup_start_time : null
      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
      point_in_time_recovery_enabled = var.enable_point_in_time_recovery
    }

    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      require_ssl     = var.require_ssl
      private_network = var.enable_private_ip ? var.private_network : null

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    user_labels = local.common_labels
  }
}

# Databases
resource "google_sql_database" "databases" {
  for_each  = { for db in var.databases : db.name => db }
  name      = each.value.name
  instance  = google_sql_database_instance.main.name
  project   = var.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

# Users
resource "google_sql_user" "users" {
  for_each = { for user in var.users : user.name => user }
  name     = each.value.name
  instance = google_sql_database_instance.main.name
  project  = var.project_id
  password = each.value.password
  host     = each.value.host
}

# =========================================
# OUTPUTS
# =========================================

output "instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "Connection name for the instance (project:region:instance)"
  value       = google_sql_database_instance.main.connection_name
}

output "public_ip_address" {
  description = "Public IP address of the instance"
  value       = var.ipv4_enabled ? google_sql_database_instance.main.public_ip_address : null
}

output "private_ip_address" {
  description = "Private IP address of the instance"
  value       = var.enable_private_ip ? google_sql_database_instance.main.private_ip_address : null
}

output "self_link" {
  description = "Self link of the Cloud SQL instance"
  value       = google_sql_database_instance.main.self_link
}

output "database_names" {
  description = "List of created database names"
  value       = [for db in google_sql_database.databases : db.name]
}

output "user_names" {
  description = "List of created user names"
  value       = [for user in google_sql_user.users : user.name]
}
