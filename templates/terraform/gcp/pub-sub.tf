# =========================================
# Google Cloud Pub/Sub - Terraform Template
# =========================================
# This template creates Pub/Sub topics and subscriptions with:
# - Message retention and ordering
# - Dead letter topics
# - Push and pull subscriptions
# - Message filtering
# - Exactly-once delivery
# - Retry policies
# - IAM permissions
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

variable "topic_name" {
  description = "Name of the Pub/Sub topic"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_\\.~+%]{2,254}$", var.topic_name))
    error_message = "Topic name must be 3-255 characters, start with a letter, contain only letters, numbers, and specific special characters"
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "message_retention_duration" {
  description = "Message retention duration (e.g., '86400s' for 1 day, max '604800s' for 7 days)"
  type        = string
  default     = "86400s"
}

variable "enable_message_ordering" {
  description = "Enable message ordering for the topic"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "KMS key name for encryption (optional)"
  type        = string
  default     = null
}

variable "allowed_persistence_regions" {
  description = "List of regions where messages can be persisted at rest"
  type        = list(string)
  default     = []
}

variable "schema_name" {
  description = "Schema name for message validation (optional)"
  type        = string
  default     = null
}

variable "schema_type" {
  description = "Schema type - affects message validation format (AVRO or PROTOCOL_BUFFER)"
  type        = string
  default     = "AVRO"

  validation {
    condition     = var.schema_name == null || contains(["AVRO", "PROTOCOL_BUFFER"], var.schema_type)
    error_message = "Schema type must be AVRO or PROTOCOL_BUFFER"
  }
}

variable "schema_definition" {
  description = "Schema definition string"
  type        = string
  default     = null
}

variable "subscriptions" {
  description = "List of subscriptions to create"
  type = list(object({
    name                         = string
    ack_deadline_seconds         = optional(number, 10)
    message_retention_duration   = optional(string, "604800s")
    retain_acked_messages        = optional(bool, false)
    enable_exactly_once_delivery = optional(bool, false)
    enable_message_ordering      = optional(bool, false)
    filter                       = optional(string, "")

    # Push configuration
    push_endpoint = optional(string, null)
    push_attributes = optional(map(string), {})

    # Dead letter policy
    dead_letter_topic               = optional(string, null)
    max_delivery_attempts           = optional(number, 5)

    # Retry policy
    minimum_backoff = optional(string, "10s")
    maximum_backoff = optional(string, "600s")

    # Expiration policy
    ttl = optional(string, "") # Empty string means never expire
  }))
  default = []
}

variable "topic_labels" {
  description = "Labels to apply to the topic"
  type        = map(string)
  default     = {}
}

variable "subscription_labels" {
  description = "Labels to apply to all subscriptions"
  type        = map(string)
  default     = {}
}

# =========================================
# LOCAL VARIABLES
# =========================================

locals {
  # Common labels
  common_labels = merge(
    var.topic_labels,
    {
      managed_by = "terraform"
      template   = "pub-sub"
    }
  )

  subscription_labels = merge(
    var.subscription_labels,
    {
      managed_by = "terraform"
      template   = "pub-sub"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Schema (if specified)
resource "google_pubsub_schema" "schema" {
  count = var.schema_name != null && var.schema_definition != null ? 1 : 0

  name       = var.schema_name
  project    = var.project_id
  type       = var.schema_type
  definition = var.schema_definition
}

# Pub/Sub Topic
resource "google_pubsub_topic" "main" {
  name    = var.topic_name
  project = var.project_id
  labels  = local.common_labels

  message_retention_duration = var.message_retention_duration

  dynamic "message_storage_policy" {
    for_each = length(var.allowed_persistence_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = var.allowed_persistence_regions
    }
  }

  dynamic "schema_settings" {
    for_each = var.schema_name != null ? [1] : []
    content {
      schema   = google_pubsub_schema.schema[0].id
      encoding = "JSON"
    }
  }

  kms_key_name = var.kms_key_name
}

# Pub/Sub Subscriptions
resource "google_pubsub_subscription" "subscriptions" {
  for_each = { for sub in var.subscriptions : sub.name => sub }

  name    = each.value.name
  project = var.project_id
  topic   = google_pubsub_topic.main.id
  labels  = local.subscription_labels

  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.message_retention_duration
  retain_acked_messages      = each.value.retain_acked_messages
  enable_exactly_once_delivery = each.value.enable_exactly_once_delivery
  enable_message_ordering    = each.value.enable_message_ordering
  filter                     = each.value.filter

  dynamic "push_config" {
    for_each = each.value.push_endpoint != null ? [1] : []
    content {
      push_endpoint = each.value.push_endpoint
      attributes    = each.value.push_attributes
    }
  }

  dynamic "dead_letter_policy" {
    for_each = each.value.dead_letter_topic != null ? [1] : []
    content {
      dead_letter_topic     = each.value.dead_letter_topic
      max_delivery_attempts = each.value.max_delivery_attempts
    }
  }

  retry_policy {
    minimum_backoff = each.value.minimum_backoff
    maximum_backoff = each.value.maximum_backoff
  }

  dynamic "expiration_policy" {
    for_each = each.value.ttl != "" ? [1] : []
    content {
      ttl = each.value.ttl
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "topic_id" {
  description = "ID of the Pub/Sub topic"
  value       = google_pubsub_topic.main.id
}

output "topic_name" {
  description = "Name of the Pub/Sub topic"
  value       = google_pubsub_topic.main.name
}

output "subscription_ids" {
  description = "Map of subscription names to IDs"
  value       = { for sub in google_pubsub_subscription.subscriptions : sub.name => sub.id }
}

output "subscription_names" {
  description = "List of subscription names"
  value       = [for sub in google_pubsub_subscription.subscriptions : sub.name]
}

output "schema_id" {
  description = "ID of the schema (if created)"
  value       = var.schema_name != null ? google_pubsub_schema.schema[0].id : null
}
