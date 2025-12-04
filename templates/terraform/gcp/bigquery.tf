# =========================================
# Google BigQuery - Terraform Template
# =========================================
# This template creates BigQuery resources with:
# - Datasets with access control
# - Tables with schemas
# - Views with SQL queries
# - Partitioning and clustering
# - Encryption with customer-managed keys
# - Data retention and expiration
# - External data sources
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

variable "dataset_id" {
  description = "ID of the BigQuery dataset"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.dataset_id))
    error_message = "Dataset ID must be 1-1024 characters, alphanumeric and underscores only"
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "Dataset location - affects data residency and query performance (US, EU, or specific region)"
  type        = string
  default = "US"
}

variable "friendly_name" {
  description = "Friendly name for the dataset"
  type        = string
  default     = ""
}

variable "description" {
  description = "Description of the dataset"
  type        = string
  default     = ""
}

variable "default_table_expiration_ms" {
  description = "Default table expiration in milliseconds (0 = never expire)"
  type        = number
  default     = 0

  validation {
    condition     = var.default_table_expiration_ms >= 0
    error_message = "Table expiration must be >= 0"
  }
}

variable "default_partition_expiration_ms" {
  description = "Default partition expiration in milliseconds (0 = never expire)"
  type        = number
  default     = 0

  validation {
    condition     = var.default_partition_expiration_ms >= 0
    error_message = "Partition expiration must be >= 0"
  }
}

variable "delete_contents_on_destroy" {
  description = "Delete dataset contents on destroy"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "KMS key name for encryption (optional)"
  type        = string
  default     = null
}

variable "max_time_travel_hours" {
  description = "Time travel window in hours (48-168)"
  type        = number
  default     = 168

  validation {
    condition     = var.max_time_travel_hours >= 48 && var.max_time_travel_hours <= 168
    error_message = "Time travel hours must be between 48 and 168"
  }
}

variable "access_entries" {
  description = "Access control entries for the dataset"
  type = list(object({
    role          = string
    user_by_email = optional(string)
    group_by_email = optional(string)
    domain        = optional(string)
    special_group = optional(string)
    iam_member    = optional(string)
  }))
  default = []
}

variable "tables" {
  description = "List of tables to create"
  type = list(object({
    table_id            = string
    description         = optional(string, "")
    deletion_protection = optional(bool, true)
    expiration_time     = optional(number, null)

    # Schema
    schema_json = optional(string, null)

    # Partitioning
    time_partitioning_type   = optional(string, null)  # DAY, HOUR, MONTH, YEAR
    time_partitioning_field  = optional(string, null)
    require_partition_filter = optional(bool, false)

    # Clustering
    clustering_fields = optional(list(string), [])

    # External data
    external_data_source_uri    = optional(string, null)
    external_data_source_format = optional(string, "CSV")  # CSV, JSON, AVRO, PARQUET
    autodetect                  = optional(bool, false)
  }))
  default = []
}

variable "views" {
  description = "List of views to create"
  type = list(object({
    view_id             = string
    description         = optional(string, "")
    deletion_protection = optional(bool, true)
    query               = string
    use_legacy_sql      = optional(bool, false)
  }))
  default = []
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
      template   = "bigquery"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# BigQuery Dataset
resource "google_bigquery_dataset" "main" {
  dataset_id  = var.dataset_id
  project     = var.project_id
  location    = var.location
  friendly_name = var.friendly_name != "" ? var.friendly_name : null
  description = var.description != "" ? var.description : null
  labels      = local.common_labels

  default_table_expiration_ms     = var.default_table_expiration_ms > 0 ? var.default_table_expiration_ms : null
  default_partition_expiration_ms = var.default_partition_expiration_ms > 0 ? var.default_partition_expiration_ms : null
  delete_contents_on_destroy      = var.delete_contents_on_destroy
  max_time_travel_hours           = "${var.max_time_travel_hours}"

  dynamic "default_encryption_configuration" {
    for_each = var.kms_key_name != null ? [1] : []
    content {
      kms_key_name = var.kms_key_name
    }
  }

  dynamic "access" {
    for_each = var.access_entries
    content {
      role           = access.value.role
      user_by_email  = access.value.user_by_email
      group_by_email = access.value.group_by_email
      domain         = access.value.domain
      special_group  = access.value.special_group
      iam_member     = access.value.iam_member
    }
  }
}

# BigQuery Tables
resource "google_bigquery_table" "tables" {
  for_each = { for table in var.tables : table.table_id => table }

  dataset_id          = google_bigquery_dataset.main.dataset_id
  table_id            = each.value.table_id
  project             = var.project_id
  description         = each.value.description
  deletion_protection = each.value.deletion_protection
  expiration_time     = each.value.expiration_time
  labels              = local.common_labels

  schema = each.value.schema_json

  dynamic "time_partitioning" {
    for_each = each.value.time_partitioning_type != null ? [1] : []
    content {
      type                     = each.value.time_partitioning_type
      field                    = each.value.time_partitioning_field
      require_partition_filter = each.value.require_partition_filter
    }
  }

  dynamic "range_partitioning" {
    for_each = []  # Can be extended for range partitioning
    content {}
  }

  clustering = length(each.value.clustering_fields) > 0 ? each.value.clustering_fields : null

  dynamic "external_data_configuration" {
    for_each = each.value.external_data_source_uri != null ? [1] : []
    content {
      source_uris   = [each.value.external_data_source_uri]
      source_format = each.value.external_data_source_format
      autodetect    = each.value.autodetect

      dynamic "csv_options" {
        for_each = each.value.external_data_source_format == "CSV" ? [1] : []
        content {
          quote                 = "\""
          skip_leading_rows     = 1
          allow_quoted_newlines = false
          allow_jagged_rows     = false
        }
      }
    }
  }
}

# BigQuery Views
resource "google_bigquery_table" "views" {
  for_each = { for view in var.views : view.view_id => view }

  dataset_id          = google_bigquery_dataset.main.dataset_id
  table_id            = each.value.view_id
  project             = var.project_id
  description         = each.value.description
  deletion_protection = each.value.deletion_protection
  labels              = local.common_labels

  view {
    query          = each.value.query
    use_legacy_sql = each.value.use_legacy_sql
  }
}

# =========================================
# OUTPUTS
# =========================================

output "dataset_id" {
  description = "ID of the BigQuery dataset"
  value       = google_bigquery_dataset.main.id
}

output "dataset_name" {
  description = "Name of the BigQuery dataset"
  value       = google_bigquery_dataset.main.dataset_id
}

output "dataset_self_link" {
  description = "Self link of the dataset"
  value       = google_bigquery_dataset.main.self_link
}

output "table_ids" {
  description = "Map of table IDs"
  value       = { for table in google_bigquery_table.tables : table.table_id => table.id }
}

output "view_ids" {
  description = "Map of view IDs"
  value       = { for view in google_bigquery_table.views : view.table_id => view.id }
}

output "dataset_location" {
  description = "Location of the dataset"
  value       = google_bigquery_dataset.main.location
}
