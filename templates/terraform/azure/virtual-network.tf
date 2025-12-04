# =========================================
# Azure Virtual Network - Terraform Template
# =========================================
# This template creates a Virtual Network with:
# - Configurable address space
# - Multiple subnets with optional service endpoints
# - DNS servers configuration
# - DDoS protection plan (optional)
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

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9._]{0,62}[a-zA-Z0-9]$", var.vnet_name))
    error_message = "VNet name must be 2-64 characters, start and end with alphanumeric, and contain only letters, numbers, hyphens, periods, and underscores"
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

variable "address_space" {
  description = "Address space for the virtual network (CIDR notation)"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "All address spaces must be valid CIDR blocks"
  }
}

variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    name              = string
    address_prefix    = string
    service_endpoints = optional(list(string), [])
  }))
  default = [
    {
      name           = "default"
      address_prefix = "10.0.1.0/24"
      service_endpoints = []
    }
  ]

  validation {
    condition     = alltrue([for subnet in var.subnets : can(cidrhost(subnet.address_prefix, 0))])
    error_message = "All subnet address prefixes must be valid CIDR blocks"
  }

  validation {
    condition     = alltrue([for subnet in var.subnets : can(regex("^[a-zA-Z0-9][-a-zA-Z0-9._]{0,78}[a-zA-Z0-9]$", subnet.name))])
    error_message = "Subnet names must be 2-80 characters, start and end with alphanumeric"
  }
}

variable "dns_servers" {
  description = "List of DNS server IP addresses (leave empty for Azure default)"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.dns_servers : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))])
    error_message = "DNS servers must be valid IP addresses"
  }
}

variable "enable_ddos_protection" {
  description = "Enable DDoS Protection Standard (additional cost applies)"
  type        = bool
  default     = false
}

variable "ddos_protection_plan_id" {
  description = "ID of existing DDoS Protection Plan (required if enable_ddos_protection is true)"
  type        = string
  default     = null
}

variable "enable_vm_protection" {
  description = "Enable VM protection for the VNet"
  type        = bool
  default     = false
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
      Template  = "virtual-network"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = length(var.dns_servers) > 0 ? var.dns_servers : null
  tags                = local.common_tags

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection && var.ddos_protection_plan_id != null ? [1] : []
    content {
      id     = var.ddos_protection_plan_id
      enable = true
    }
  }
}

# Subnets
resource "azurerm_subnet" "subnets" {
  for_each             = { for subnet in var.subnets : subnet.name => subnet }
  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = each.value.service_endpoints
}

# =========================================
# OUTPUTS
# =========================================

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "vnet_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.id }
}

output "subnet_address_prefixes" {
  description = "Map of subnet names to their address prefixes"
  value       = { for name, subnet in azurerm_subnet.subnets : name => subnet.address_prefixes }
}

output "dns_servers" {
  description = "DNS servers configured for the VNet"
  value       = azurerm_virtual_network.main.dns_servers
}
