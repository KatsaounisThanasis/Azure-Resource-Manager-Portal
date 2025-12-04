# =========================================
# Azure Container Registry (ACR) - Terraform Template
# =========================================
# This template creates a Container Registry with:
# - Basic, Standard, or Premium SKU
# - Geo-replication (Premium SKU)
# - Webhook support
# - Network rules and private endpoints
# - Content trust and vulnerability scanning
# - Image retention policies
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

variable "acr_name" {
  description = "Name of the container registry (5-50 chars, alphanumeric only)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR name must be 5-50 alphanumeric characters only"
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

variable "sku" {
  description = "SKU for the container registry - affects cost and features (Basic = 10GB storage, Standard = 100GB storage, Premium = 500GB storage with geo-replication and content trust)"
  type        = string

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium"
  }
}

variable "admin_enabled" {
  description = "Enable admin user for the registry"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy (requires Premium SKU)"
  type        = bool
  default     = false
}

variable "export_policy_enabled" {
  description = "Enable export policy"
  type        = bool
  default     = true
}

variable "quarantine_policy_enabled" {
  description = "Enable quarantine policy (requires Premium SKU)"
  type        = bool
  default     = false
}

variable "retention_policy_days" {
  description = "Number of days to retain untagged manifests (requires Premium SKU, 0-365)"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_policy_days >= 0 && var.retention_policy_days <= 365
    error_message = "Retention policy days must be between 0 and 365"
  }
}

variable "trust_policy_enabled" {
  description = "Enable content trust policy (requires Premium SKU)"
  type        = bool
  default     = false
}

variable "network_rule_set_default_action" {
  description = "Default action for network rules - affects security (Allow = open access, Deny = restricted access with firewall rules)"
  type        = string

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rule_set_default_action)
    error_message = "Network rule set default action must be Allow or Deny"
  }
}

variable "ip_rules" {
  description = "List of IP addresses or CIDR ranges allowed to access ACR"
  type        = list(string)
  default     = []
}

variable "virtual_network_rules" {
  description = "List of subnet IDs allowed to access ACR"
  type        = list(string)
  default     = []
}

variable "georeplications" {
  description = "List of regions for geo-replication (requires Premium SKU)"
  type = list(object({
    location                  = string
    zone_redundancy_enabled   = optional(bool, false)
    regional_endpoint_enabled = optional(bool, false)
  }))
  default = []
}

variable "enable_webhook" {
  description = "Enable webhook for registry events"
  type        = bool
  default     = false
}

variable "webhook_name" {
  description = "Name of the webhook"
  type        = string
  default     = ""
}

variable "webhook_service_uri" {
  description = "Service URI for the webhook"
  type        = string
  default     = ""
}

variable "webhook_actions" {
  description = "List of actions that trigger the webhook"
  type        = list(string)
  default     = ["push", "delete"]

  validation {
    condition = alltrue([
      for action in var.webhook_actions :
      contains(["push", "delete", "quarantine", "chart_push", "chart_delete"], action)
    ])
    error_message = "Webhook actions must be push, delete, quarantine, chart_push, or chart_delete"
  }
}

variable "enable_encryption" {
  description = "Enable customer-managed key encryption (requires Premium SKU)"
  type        = bool
  default     = false
}

variable "encryption_key_vault_key_id" {
  description = "Key Vault key ID for encryption (required if enable_encryption is true)"
  type        = string
  default     = null
}

variable "encryption_identity_client_id" {
  description = "Client ID of user-assigned identity for encryption (required if enable_encryption is true)"
  type        = string
  default     = null
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
  # Webhook name
  webhook_name_final = var.enable_webhook ? (
    var.webhook_name != "" ? var.webhook_name : "${var.acr_name}webhook"
  ) : ""

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "container-registry"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Container Registry
resource "azurerm_container_registry" "main" {
  name                          = var.acr_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku
  admin_enabled                 = var.admin_enabled
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = var.sku == "Premium" ? var.zone_redundancy_enabled : false
  export_policy_enabled         = var.export_policy_enabled
  quarantine_policy_enabled     = var.sku == "Premium" ? var.quarantine_policy_enabled : false
  tags                          = local.common_tags

  dynamic "retention_policy" {
    for_each = var.sku == "Premium" && var.retention_policy_days > 0 ? [1] : []
    content {
      days    = var.retention_policy_days
      enabled = true
    }
  }

  dynamic "trust_policy" {
    for_each = var.sku == "Premium" && var.trust_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "network_rule_set" {
    for_each = var.sku == "Premium" && (length(var.ip_rules) > 0 || length(var.virtual_network_rules) > 0) ? [1] : []
    content {
      default_action = var.network_rule_set_default_action

      dynamic "ip_rule" {
        for_each = var.ip_rules
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }

      dynamic "virtual_network" {
        for_each = var.virtual_network_rules
        content {
          action    = "Allow"
          subnet_id = virtual_network.value
        }
      }
    }
  }

  dynamic "georeplications" {
    for_each = var.sku == "Premium" ? var.georeplications : []
    content {
      location                  = georeplications.value.location
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
      tags                      = local.common_tags
    }
  }

  dynamic "encryption" {
    for_each = var.sku == "Premium" && var.enable_encryption && var.encryption_key_vault_key_id != null ? [1] : []
    content {
      enabled            = true
      key_vault_key_id   = var.encryption_key_vault_key_id
      identity_client_id = var.encryption_identity_client_id
    }
  }

  identity {
    type = var.enable_encryption ? "UserAssigned" : "SystemAssigned"
    identity_ids = var.enable_encryption && var.encryption_identity_client_id != null ? [
      var.encryption_identity_client_id
    ] : null
  }
}

# Webhook
resource "azurerm_container_registry_webhook" "main" {
  count               = var.enable_webhook ? 1 : 0
  name                = local.webhook_name_final
  location            = var.location
  resource_group_name = var.resource_group_name
  registry_name       = azurerm_container_registry.main.name
  service_uri         = var.webhook_service_uri
  actions             = var.webhook_actions
  status              = "enabled"
  tags                = local.common_tags
}

# =========================================
# OUTPUTS
# =========================================

output "acr_id" {
  description = "ID of the container registry"
  value       = azurerm_container_registry.main.id
}

output "acr_name" {
  description = "Name of the container registry"
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Login server URL for the container registry"
  value       = azurerm_container_registry.main.login_server
}

output "admin_username" {
  description = "Admin username (if admin is enabled)"
  value       = var.admin_enabled ? azurerm_container_registry.main.admin_username : null
}

output "admin_password" {
  description = "Admin password (if admin is enabled)"
  value       = var.admin_enabled ? azurerm_container_registry.main.admin_password : null
  sensitive   = true
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity"
  value       = azurerm_container_registry.main.identity[0].principal_id
}

output "webhook_id" {
  description = "ID of the webhook (if enabled)"
  value       = var.enable_webhook ? azurerm_container_registry_webhook.main[0].id : null
}
