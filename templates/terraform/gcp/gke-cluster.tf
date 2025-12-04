# =========================================
# Google Kubernetes Engine (GKE) Cluster - Terraform Template
# =========================================
# This template creates a GKE cluster with:
# - Autopilot or Standard mode
# - Multiple node pools
# - Auto-scaling and auto-repair
# - Network configuration
# - Workload Identity
# - Private cluster support
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

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.cluster_name))
    error_message = "Cluster name must start with lowercase letter, be 1-40 characters, contain only lowercase letters, numbers, and hyphens"
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

variable "location_type" {
  description = "Location type - affects cost and availability (regional=higher availability/cost, zonal=single zone/lower cost)"
  type        = string
  default = "US"
}

variable "zones" {
  description = "List of zones for the cluster (for zonal, specify one zone)"
  type        = list(string)
  default     = []
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork name"
  type        = string
  default     = "default"
}

variable "enable_autopilot" {
  description = "Enable Autopilot mode (fully managed)"
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes version (latest if not specified)"
  type        = string
  default     = ""
}

variable "release_channel" {
  description = "Release channel - affects update frequency (RAPID=latest features, REGULAR=balanced, STABLE=production-ready with delayed updates)"
  type        = string

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "Release channel must be RAPID, REGULAR, STABLE, or UNSPECIFIED"
  }
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

variable "enable_private_cluster" {
  description = "Enable private cluster (private nodes)"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "IPv4 CIDR block for master (required if enable_private_cluster is true)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_master_authorized_networks" {
  description = "Enable master authorized networks"
  type        = bool
  default     = false
}

variable "master_authorized_networks_cidr_blocks" {
  description = "List of CIDR blocks authorized to access the master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# Node Pool Configuration (Standard mode only)
variable "node_pools" {
  description = "List of node pools"
  type = list(object({
    name               = string
    machine_type       = string
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-standard")
    initial_node_count = optional(number, 1)
    min_node_count     = optional(number, 1)
    max_node_count     = optional(number, 3)
    enable_autoscaling = optional(bool, true)
    enable_autorepair  = optional(bool, true)
    enable_autoupgrade = optional(bool, true)
    preemptible        = optional(bool, false)
    spot               = optional(bool, false)
  }))
  default = [
    {
      name               = "default-pool"
      machine_type       = "e2-medium"
      initial_node_count = 1
      min_node_count     = 1
      max_node_count     = 3
    }
  ]
}

variable "enable_http_load_balancing" {
  description = "Enable HTTP load balancing add-on"
  type        = bool
  default     = true
}

variable "enable_horizontal_pod_autoscaling" {
  description = "Enable horizontal pod autoscaling"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy enforcement"
  type        = bool
  default     = false
}

variable "maintenance_start_time" {
  description = "Maintenance window start time (HH:MM format)"
  type        = string
  default     = "03:00"
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
  # Location (region or zone)
  location = var.location_type == "zonal" && length(var.zones) > 0 ? var.zones[0] : var.region

  # Common labels
  common_labels = merge(
    var.labels,
    {
      managed_by = "terraform"
      template   = "gke-cluster"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# GKE Cluster
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  project  = var.project_id
  location = local.location

  # Autopilot or Standard mode
  enable_autopilot = var.enable_autopilot

  network    = var.network
  subnetwork = var.subnetwork

  # Initial node count (removed after initial creation if node pools are used)
  remove_default_node_pool = !var.enable_autopilot
  initial_node_count       = var.enable_autopilot ? null : 1

  # Kubernetes version
  min_master_version = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Release channel
  release_channel {
    channel = var.release_channel
  }

  # Workload Identity
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = var.enable_master_authorized_networks ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks_cidr_blocks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Add-ons
  addons_config {
    http_load_balancing {
      disabled = !var.enable_http_load_balancing
    }
    horizontal_pod_autoscaling {
      disabled = !var.enable_horizontal_pod_autoscaling
    }
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }

  # Network policy
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled  = true
      provider = "CALICO"
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Deletion protection
  deletion_protection = var.deletion_protection

  # Resource labels
  resource_labels = local.common_labels
}

# Node Pools (Standard mode only)
resource "google_container_node_pool" "pools" {
  for_each = var.enable_autopilot ? {} : { for pool in var.node_pools : pool.name => pool }

  name       = each.value.name
  cluster    = google_container_cluster.main.id
  location   = local.location
  project    = var.project_id

  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  management {
    auto_repair  = each.value.enable_autorepair
    auto_upgrade = each.value.enable_autoupgrade
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    preemptible  = each.value.preemptible
    spot         = each.value.spot

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = local.common_labels

    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "CA certificate of the cluster"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.main.id
}

output "master_version" {
  description = "Kubernetes master version"
  value       = google_container_cluster.main.master_version
}

output "node_pool_names" {
  description = "List of node pool names"
  value       = var.enable_autopilot ? [] : [for pool in google_container_node_pool.pools : pool.name]
}
