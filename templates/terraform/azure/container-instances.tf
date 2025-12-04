# =========================================
# Azure Container Instances (ACI) - Terraform Template
# =========================================
# This template creates Container Instances with:
# - Single or multiple containers
# - Custom resource limits (CPU, memory)
# - Environment variables and secrets
# - Volume mounts (Azure Files, Empty Dir, Git Repo)
# - Network profile with VNet integration
# - Public or private IP
#
# Version: 1.0
# Last Updated: 2025-11-15
# =========================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# =========================================
# VARIABLES
# =========================================

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "container_group_name" {
  description = "Name of the container group"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,63}$", var.container_group_name))
    error_message = "Container group name must be 1-63 characters, letters, numbers, and hyphens"
  }
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string

  validation {
    condition     = can(regex("^[-\\w\\._\\(\\)]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, underscores, hyphens, periods, and parentheses"
  }
}

variable "os_type" {
  description = "Operating system type (Linux or Windows)"
  type        = string
  default     = "Linux"

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be Linux or Windows"
  }
}

variable "restart_policy" {
  description = "Restart policy for containers (Always, Never, OnFailure)"
  type        = string
  default     = "Always"

  validation {
    condition     = contains(["Always", "Never", "OnFailure"], var.restart_policy)
    error_message = "Restart policy must be Always, Never, or OnFailure"
  }
}

variable "containers" {
  description = "List of containers in the group"
  type = list(object({
    name   = string
    image  = string
    cpu    = number
    memory = number
    ports = optional(list(object({
      port     = number
      protocol = string
    })), [])
    environment_variables = optional(map(string), {})
    secure_environment_variables = optional(map(string), {})
    commands = optional(list(string), [])
  }))

  validation {
    condition     = length(var.containers) > 0
    error_message = "At least one container must be specified"
  }
}

variable "ip_address_type" {
  description = "IP address type (Public, Private, or None)"
  type        = string
  default     = "Public"

  validation {
    condition     = contains(["Public", "Private", "None"], var.ip_address_type)
    error_message = "IP address type must be Public, Private, or None"
  }
}

variable "dns_name_label" {
  description = "DNS name label for the public IP"
  type        = string
  default     = ""

  validation {
    condition     = var.dns_name_label == "" || can(regex("^[a-z0-9-]{3,63}$", var.dns_name_label))
    error_message = "DNS name label must be 3-63 lowercase alphanumeric characters and hyphens"
  }
}

variable "exposed_ports" {
  description = "List of ports to expose on the container group"
  type = list(object({
    port     = number
    protocol = string
  }))
  default = []
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (required if ip_address_type is Private)"
  type        = string
  default     = null
}

variable "enable_azure_files_volume" {
  description = "Enable Azure Files volume mount"
  type        = bool
  default     = false
}

variable "azure_files_volume_name" {
  description = "Name of the Azure Files volume"
  type        = string
  default     = "azurefile"
}

variable "azure_files_share_name" {
  description = "Azure Files share name (required if enable_azure_files_volume is true)"
  type        = string
  default     = ""
}

variable "azure_files_storage_account_name" {
  description = "Storage account name for Azure Files (required if enable_azure_files_volume is true)"
  type        = string
  default     = ""
}

variable "azure_files_storage_account_key" {
  description = "Storage account key for Azure Files (required if enable_azure_files_volume is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_files_mount_path" {
  description = "Mount path for Azure Files volume"
  type        = string
  default     = "/mnt/azurefile"
}

variable "enable_empty_dir_volume" {
  description = "Enable empty directory volume"
  type        = bool
  default     = false
}

variable "empty_dir_volume_name" {
  description = "Name of the empty directory volume"
  type        = string
  default     = "emptydir"
}

variable "enable_git_repo_volume" {
  description = "Enable Git repository volume"
  type        = bool
  default     = false
}

variable "git_repo_volume_name" {
  description = "Name of the Git repository volume"
  type        = string
  default     = "gitrepo"
}

variable "git_repo_url" {
  description = "Git repository URL (required if enable_git_repo_volume is true)"
  type        = string
  default     = ""
}

variable "git_repo_directory" {
  description = "Directory path in the Git repository"
  type        = string
  default     = "."
}

variable "git_repo_revision" {
  description = "Git revision (commit hash or branch)"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =========================================
# LOCAL VARIABLES
# =========================================

locals {
  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "container-instances"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Container Group
resource "azurerm_container_group" "main" {
  name                = var.container_group_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = var.os_type
  restart_policy      = var.restart_policy
  ip_address_type     = var.ip_address_type
  dns_name_label      = var.ip_address_type == "Public" && var.dns_name_label != "" ? var.dns_name_label : null
  subnet_ids          = var.ip_address_type == "Private" && var.subnet_id != null ? [var.subnet_id] : null
  tags                = local.common_tags

  dynamic "container" {
    for_each = var.containers
    content {
      name   = container.value.name
      image  = container.value.image
      cpu    = container.value.cpu
      memory = container.value.memory

      dynamic "ports" {
        for_each = container.value.ports
        content {
          port     = ports.value.port
          protocol = ports.value.protocol
        }
      }

      environment_variables        = container.value.environment_variables
      secure_environment_variables = container.value.secure_environment_variables
      commands                     = length(container.value.commands) > 0 ? container.value.commands : null

      dynamic "volume" {
        for_each = var.enable_azure_files_volume ? [1] : []
        content {
          name       = var.azure_files_volume_name
          mount_path = var.azure_files_mount_path
          read_only  = false
          share_name = var.azure_files_share_name

          storage_account_name = var.azure_files_storage_account_name
          storage_account_key  = var.azure_files_storage_account_key
        }
      }

      dynamic "volume" {
        for_each = var.enable_empty_dir_volume ? [1] : []
        content {
          name       = var.empty_dir_volume_name
          mount_path = "/mnt/emptydir"
          read_only  = false
          empty_dir  = true
        }
      }

      dynamic "volume" {
        for_each = var.enable_git_repo_volume ? [1] : []
        content {
          name       = var.git_repo_volume_name
          mount_path = "/mnt/gitrepo"
          read_only  = true

          git_repo {
            url       = var.git_repo_url
            directory = var.git_repo_directory
            revision  = var.git_repo_revision
          }
        }
      }
    }
  }

  dynamic "exposed_port" {
    for_each = var.ip_address_type != "None" ? var.exposed_ports : []
    content {
      port     = exposed_port.value.port
      protocol = exposed_port.value.protocol
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "container_group_id" {
  description = "ID of the container group"
  value       = azurerm_container_group.main.id
}

output "container_group_name" {
  description = "Name of the container group"
  value       = azurerm_container_group.main.name
}

output "ip_address" {
  description = "IP address of the container group"
  value       = var.ip_address_type != "None" ? azurerm_container_group.main.ip_address : null
}

output "fqdn" {
  description = "FQDN of the container group (if DNS name label is set)"
  value       = var.ip_address_type == "Public" && var.dns_name_label != "" ? azurerm_container_group.main.fqdn : null
}
