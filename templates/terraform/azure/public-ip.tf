# =========================================
# Azure Public IP - Terraform Template
# =========================================
# This template creates a Public IP address with:
# - Static or Dynamic allocation
# - Standard or Basic SKU
# - IPv4 or IPv6 support
# - DNS label configuration
# - Availability zones support
# - DDoS protection
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

variable "public_ip_name" {
  description = "Name of the public IP"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]{1,80}$", var.public_ip_name))
    error_message = "Public IP name must be 1-80 characters"
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

variable "allocation_method" {
  description = "Allocation method for the public IP - affects IP persistence (Static=IP never changes, Dynamic=IP may change when deallocated)"
  type        = string
  default = "eastus"
}

variable "sku" {
  description = "SKU for the public IP - affects features and cost (Basic=lower cost with limited features, Standard=zone-redundant with advanced features)"
  type        = string

  validation {
    condition     = contains(["Basic", "Standard"], var.sku)
    error_message = "SKU must be Basic or Standard"
  }
}

variable "sku_tier" {
  description = "SKU tier (Regional or Global)"
  type        = string
  default     = "Regional"

  validation {
    condition     = contains(["Regional", "Global"], var.sku_tier)
    error_message = "SKU tier must be Regional or Global"
  }
}

variable "ip_version" {
  description = "IP version (IPv4 or IPv6)"
  type        = string
  default     = "IPv4"

  validation {
    condition     = contains(["IPv4", "IPv6"], var.ip_version)
    error_message = "IP version must be IPv4 or IPv6"
  }
}

variable "domain_name_label" {
  description = "DNS label for the public IP (creates <label>.<region>.cloudapp.azure.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name_label == "" || can(regex("^[a-z0-9-]{3,63}$", var.domain_name_label))
    error_message = "Domain name label must be 3-63 lowercase alphanumeric characters and hyphens"
  }
}

variable "idle_timeout_in_minutes" {
  description = "Idle timeout for TCP connections in minutes (4-30)"
  type        = number
  default     = 4

  validation {
    condition     = var.idle_timeout_in_minutes >= 4 && var.idle_timeout_in_minutes <= 30
    error_message = "Idle timeout must be between 4 and 30 minutes"
  }
}

variable "availability_zone" {
  description = "Availability zone for the public IP (leave empty for non-zonal, or specify 1, 2, 3)"
  type        = string
  default     = ""
}

variable "enable_ddos_protection" {
  description = "Enable DDoS protection (requires Standard SKU)"
  type        = bool
  default     = false
}

variable "ddos_protection_plan_id" {
  description = "ID of DDoS protection plan (required if enable_ddos_protection is true)"
  type        = string
  default     = null
}

variable "reverse_fqdn" {
  description = "Reverse FQDN for the public IP"
  type        = string
  default     = ""
}

variable "public_ip_prefix_id" {
  description = "ID of public IP prefix to allocate from"
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
  # Availability zones
  zones = var.availability_zone != "" ? [var.availability_zone] : []

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "public-ip"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# DDoS Protection Plan
resource "azurerm_network_ddos_protection_plan" "main" {
  count               = var.enable_ddos_protection && var.ddos_protection_plan_id == null ? 1 : 0
  name                = "${var.public_ip_name}-ddos-plan"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                    = var.public_ip_name
  location                = var.location
  resource_group_name     = var.resource_group_name
  allocation_method       = var.allocation_method
  sku                     = var.sku
  sku_tier                = var.sku_tier
  ip_version              = var.ip_version
  domain_name_label       = var.domain_name_label != "" ? var.domain_name_label : null
  idle_timeout_in_minutes = var.idle_timeout_in_minutes
  zones                   = local.zones
  reverse_fqdn            = var.reverse_fqdn != "" ? var.reverse_fqdn : null
  public_ip_prefix_id     = var.public_ip_prefix_id
  tags                    = local.common_tags

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = var.ddos_protection_plan_id != null ? var.ddos_protection_plan_id : azurerm_network_ddos_protection_plan.main[0].id
      enable = true
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "public_ip_id" {
  description = "ID of the public IP"
  value       = azurerm_public_ip.main.id
}

output "public_ip_name" {
  description = "Name of the public IP"
  value       = azurerm_public_ip.main.name
}

output "ip_address" {
  description = "The IP address value (may be empty until assigned)"
  value       = azurerm_public_ip.main.ip_address
}

output "fqdn" {
  description = "Fully qualified domain name (if domain_name_label is set)"
  value       = azurerm_public_ip.main.fqdn
}

output "ddos_protection_plan_id" {
  description = "ID of the DDoS protection plan (if created)"
  value       = var.enable_ddos_protection && var.ddos_protection_plan_id == null ? azurerm_network_ddos_protection_plan.main[0].id : var.ddos_protection_plan_id
}
