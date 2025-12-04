# =========================================
# Azure Key Vault - Terraform Template
# =========================================
# This template creates a Key Vault with:
# - Soft delete and purge protection
# - Access policies for users and service principals
# - Network ACLs configuration
# - RBAC support
# - Diagnostic settings
# - Secrets, keys, and certificates support
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
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
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

variable "key_vault_name" {
  description = "Name of the key vault (3-24 characters, alphanumeric and hyphens)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key vault name must be 3-24 characters, letters, numbers, and hyphens"
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

variable "sku_name" {
  description = "SKU for the key vault - affects features and cost (standard=software-protected keys, premium=adds HSM-protected keys)"
  type        = string

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU name must be standard or premium"
  }
}

variable "enabled_for_disk_encryption" {
  description = "Enable Azure Disk Encryption to retrieve secrets"
  type        = bool
  default     = true
}

variable "enabled_for_deployment" {
  description = "Enable Azure Virtual Machines to retrieve certificates"
  type        = bool
  default     = true
}

variable "enabled_for_template_deployment" {
  description = "Enable Azure Resource Manager to retrieve secrets"
  type        = bool
  default     = true
}

variable "enable_rbac_authorization" {
  description = "Use Azure RBAC for authorization instead of access policies"
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Days to retain soft-deleted items (7-90)"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90"
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection (cannot be disabled once enabled)"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "Default action for network ACLs (Allow or Deny)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Network ACLs default action must be Allow or Deny"
  }
}

variable "network_acls_bypass" {
  description = "Bypass network ACLs for Azure services"
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["None", "AzureServices"], var.network_acls_bypass)
    error_message = "Network ACLs bypass must be None or AzureServices"
  }
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses or CIDR ranges allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "access_policies" {
  description = "List of access policies for Key Vault"
  type = list(object({
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = []
}

variable "secrets" {
  description = "Map of secrets to create in the Key Vault"
  type = map(object({
    value        = string
    content_type = optional(string, "")
  }))
  default   = {}
  sensitive = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =========================================
# DATA SOURCES
# =========================================

data "azurerm_client_config" "current" {}

# =========================================
# LOCAL VARIABLES
# =========================================

locals {
  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "key-vault"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Key Vault
resource "azurerm_key_vault" "main" {
  name                        = var.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.sku_name
  enabled_for_disk_encryption = var.enabled_for_disk_encryption
  enabled_for_deployment      = var.enabled_for_deployment
  enabled_for_template_deployment = var.enabled_for_template_deployment
  enable_rbac_authorization   = var.enable_rbac_authorization
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.purge_protection_enabled
  public_network_access_enabled = var.public_network_access_enabled
  tags                        = local.common_tags

  network_acls {
    default_action             = var.network_acls_default_action
    bypass                     = var.network_acls_bypass
    ip_rules                   = var.allowed_ip_addresses
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }
}

# Access Policies
resource "azurerm_key_vault_access_policy" "policies" {
  for_each = { for idx, policy in var.access_policies : idx => policy }

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value.object_id

  key_permissions         = each.value.key_permissions
  secret_permissions      = each.value.secret_permissions
  certificate_permissions = each.value.certificate_permissions
  storage_permissions     = each.value.storage_permissions
}

# Current user access policy (for Terraform to manage secrets)
resource "azurerm_key_vault_access_policy" "terraform" {
  count = !var.enable_rbac_authorization ? 1 : 0

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge"
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge"
  ]

  storage_permissions = [
    "Get", "List", "Set", "Delete", "Purge"
  ]
}

# Secrets
resource "azurerm_key_vault_secret" "secrets" {
  for_each = var.secrets

  name         = each.key
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id
  content_type = each.value.content_type

  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}

# =========================================
# OUTPUTS
# =========================================

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "secret_ids" {
  description = "Map of secret names to their IDs"
  value       = { for name, secret in azurerm_key_vault_secret.secrets : name => secret.id }
}
