# Azure Storage Account via Terraform
# This provides an alternative to Bicep for Azure deployments

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account (3-24 lowercase alphanumeric characters)"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters"
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
  default = "eastus"
}

variable "account_tier" {
  type        = string
  description = "Storage account tier - affects cost and features (Standard=general purpose, Premium=high performance for VMs and files)"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be Standard or Premium"
  }
}

variable "account_replication_type" {
  type        = string
  description = "Replication type - affects cost and redundancy level (LRS=lowest cost/3 copies locally, ZRS=zone redundancy, GRS=geo-redundancy, RAGRS=read-access geo-redundancy)"

  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.account_replication_type)
    error_message = "Invalid replication type"
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default = {
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type

  # Security settings
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # Blob properties
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# Private endpoint (optional, commented out for public access)
# resource "azurerm_private_endpoint" "storage" {
#   name                = "${var.storage_account_name}-pe"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#   subnet_id           = var.subnet_id
#
#   private_service_connection {
#     name                           = "${var.storage_account_name}-psc"
#     private_connection_resource_id = azurerm_storage_account.main.id
#     subresource_names              = ["blob"]
#     is_manual_connection           = false
#   }
# }

# Outputs
output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Primary access key"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}
