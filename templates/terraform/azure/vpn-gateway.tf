# =========================================
# Azure VPN Gateway - Terraform Template
# =========================================
# This template creates a VPN Gateway with:
# - VPN or ExpressRoute gateway
# - Site-to-site and point-to-site VPN
# - Active-active mode support
# - BGP configuration
# - Multiple connections
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

variable "vpn_gateway_name" {
  description = "Name of the VPN gateway"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]{1,80}$", var.vpn_gateway_name))
    error_message = "VPN gateway name must be 1-80 characters"
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

variable "type" {
  description = "Type of gateway (Vpn or ExpressRoute)"
  type        = string
  default     = "Vpn"

  validation {
    condition     = contains(["Vpn", "ExpressRoute"], var.type)
    error_message = "Type must be Vpn or ExpressRoute"
  }
}

variable "vpn_type" {
  description = "VPN type (RouteBased or PolicyBased)"
  type        = string
  default     = "RouteBased"

  validation {
    condition     = contains(["RouteBased", "PolicyBased"], var.vpn_type)
    error_message = "VPN type must be RouteBased or PolicyBased"
  }
}

variable "sku" {
  description = "SKU for the VPN gateway (Basic, VpnGw1, VpnGw2, VpnGw3, VpnGw4, VpnGw5)"
  type        = string
  default     = "VpnGw1"

  validation {
    condition     = contains(["Basic", "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5", "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"], var.sku)
    error_message = "Invalid SKU"
  }
}

variable "generation" {
  description = "Generation of the VPN gateway (Generation1 or Generation2)"
  type        = string
  default     = "Generation1"

  validation {
    condition     = contains(["Generation1", "Generation2"], var.generation)
    error_message = "Generation must be Generation1 or Generation2"
  }
}

variable "enable_bgp" {
  description = "Enable BGP for the VPN gateway"
  type        = bool
  default     = false
}

variable "active_active_enabled" {
  description = "Enable active-active mode (requires two public IPs)"
  type        = bool
  default     = false
}

variable "gateway_subnet_id" {
  description = "Subnet ID for the gateway (must be named 'GatewaySubnet')"
  type        = string
}

variable "public_ip_id_1" {
  description = "Public IP address ID for the first gateway instance"
  type        = string
}

variable "public_ip_id_2" {
  description = "Public IP address ID for the second gateway instance (required if active_active_enabled is true)"
  type        = string
  default     = null
}

variable "bgp_asn" {
  description = "ASN for BGP configuration"
  type        = number
  default     = 65515
}

variable "bgp_peering_address" {
  description = "BGP peering address"
  type        = string
  default     = ""
}

variable "vpn_client_configuration_enabled" {
  description = "Enable point-to-site VPN client configuration"
  type        = bool
  default     = false
}

variable "vpn_client_address_space" {
  description = "Address space for VPN clients"
  type        = list(string)
  default     = []
}

variable "vpn_client_protocols" {
  description = "VPN client protocols"
  type        = list(string)
  default     = ["IkeV2", "OpenVPN"]

  validation {
    condition = alltrue([
      for protocol in var.vpn_client_protocols :
      contains(["IkeV2", "OpenVPN", "SSTP"], protocol)
    ])
    error_message = "VPN client protocols must be IkeV2, OpenVPN, or SSTP"
  }
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
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "vpn-gateway"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

resource "azurerm_virtual_network_gateway" "main" {
  name                = var.vpn_gateway_name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = var.type
  vpn_type            = var.type == "Vpn" ? var.vpn_type : null
  sku                 = var.sku
  generation          = var.type == "Vpn" ? var.generation : null
  enable_bgp          = var.enable_bgp
  active_active       = var.active_active_enabled
  tags                = local.common_tags

  ip_configuration {
    name                          = "vnetGatewayConfig1"
    public_ip_address_id          = var.public_ip_id_1
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.gateway_subnet_id
  }

  dynamic "ip_configuration" {
    for_each = var.active_active_enabled && var.public_ip_id_2 != null ? [1] : []
    content {
      name                          = "vnetGatewayConfig2"
      public_ip_address_id          = var.public_ip_id_2
      private_ip_address_allocation = "Dynamic"
      subnet_id                     = var.gateway_subnet_id
    }
  }

  dynamic "bgp_settings" {
    for_each = var.enable_bgp ? [1] : []
    content {
      asn = var.bgp_asn
    }
  }

  dynamic "vpn_client_configuration" {
    for_each = var.vpn_client_configuration_enabled ? [1] : []
    content {
      address_space        = var.vpn_client_address_space
      vpn_client_protocols = var.vpn_client_protocols
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "vpn_gateway_id" {
  description = "ID of the VPN gateway"
  value       = azurerm_virtual_network_gateway.main.id
}

output "vpn_gateway_name" {
  description = "Name of the VPN gateway"
  value       = azurerm_virtual_network_gateway.main.name
}

output "bgp_asn" {
  description = "BGP ASN of the VPN gateway"
  value       = var.enable_bgp ? azurerm_virtual_network_gateway.main.bgp_settings[0].asn : null
}

output "bgp_peering_address" {
  description = "BGP peering address"
  value       = var.enable_bgp ? azurerm_virtual_network_gateway.main.bgp_settings[0].peering_address : null
}
