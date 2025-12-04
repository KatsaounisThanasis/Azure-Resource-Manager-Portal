# =========================================
# Azure Network Security Group - Terraform Template
# =========================================
# This template creates a Network Security Group with:
# - Configurable security rules
# - Support for both inbound and outbound rules
# - Common rule presets (SSH, RDP, HTTP, HTTPS)
# - Flexible rule priorities and configurations
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

variable "nsg_name" {
  description = "Name of the network security group"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9._]{0,78}[a-zA-Z0-9]$", var.nsg_name))
    error_message = "NSG name must be 2-80 characters, start and end with alphanumeric"
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

variable "security_rules" {
  description = "List of security rules to create"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = optional(string, "*")
    destination_port_range     = optional(string, "*")
    source_address_prefix      = optional(string, "*")
    destination_address_prefix = optional(string, "*")
    description                = optional(string, "")
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      rule.priority >= 100 && rule.priority <= 4096
    ])
    error_message = "Security rule priorities must be between 100 and 4096"
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      contains(["Inbound", "Outbound"], rule.direction)
    ])
    error_message = "Security rule direction must be Inbound or Outbound"
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      contains(["Allow", "Deny"], rule.access)
    ])
    error_message = "Security rule access must be Allow or Deny"
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)
    ])
    error_message = "Security rule protocol must be Tcp, Udp, Icmp, Esp, Ah, or *"
  }
}

# Common Rule Presets
variable "enable_ssh_rule" {
  description = "Enable SSH access rule (port 22)"
  type        = bool
  default     = false
}

variable "ssh_source_address_prefix" {
  description = "Source address prefix for SSH rule"
  type        = string
  default     = "*"
}

variable "enable_rdp_rule" {
  description = "Enable RDP access rule (port 3389)"
  type        = bool
  default     = false
}

variable "rdp_source_address_prefix" {
  description = "Source address prefix for RDP rule"
  type        = string
  default     = "*"
}

variable "enable_http_rule" {
  description = "Enable HTTP access rule (port 80)"
  type        = bool
  default     = false
}

variable "http_source_address_prefix" {
  description = "Source address prefix for HTTP rule"
  type        = string
  default     = "*"
}

variable "enable_https_rule" {
  description = "Enable HTTPS access rule (port 443)"
  type        = bool
  default     = false
}

variable "https_source_address_prefix" {
  description = "Source address prefix for HTTPS rule"
  type        = string
  default     = "*"
}

variable "enable_sql_rule" {
  description = "Enable SQL Server access rule (port 1433)"
  type        = bool
  default     = false
}

variable "sql_source_address_prefix" {
  description = "Source address prefix for SQL rule"
  type        = string
  default     = "VirtualNetwork"
}

variable "enable_postgres_rule" {
  description = "Enable PostgreSQL access rule (port 5432)"
  type        = bool
  default     = false
}

variable "postgres_source_address_prefix" {
  description = "Source address prefix for PostgreSQL rule"
  type        = string
  default     = "VirtualNetwork"
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
  # Common rule presets
  preset_rules = concat(
    var.enable_ssh_rule ? [{
      name                       = "AllowSSH"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.ssh_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow SSH access"
    }] : [],
    var.enable_rdp_rule ? [{
      name                       = "AllowRDP"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.rdp_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow RDP access"
    }] : [],
    var.enable_http_rule ? [{
      name                       = "AllowHTTP"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = var.http_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow HTTP access"
    }] : [],
    var.enable_https_rule ? [{
      name                       = "AllowHTTPS"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = var.https_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow HTTPS access"
    }] : [],
    var.enable_sql_rule ? [{
      name                       = "AllowSQL"
      priority                   = 1040
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1433"
      source_address_prefix      = var.sql_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow SQL Server access"
    }] : [],
    var.enable_postgres_rule ? [{
      name                       = "AllowPostgreSQL"
      priority                   = 1050
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5432"
      source_address_prefix      = var.postgres_source_address_prefix
      destination_address_prefix = "*"
      description                = "Allow PostgreSQL access"
    }] : []
  )

  # Combine preset rules with custom rules
  all_security_rules = concat(local.preset_rules, var.security_rules)

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "network-security-group"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

# Security Rules
resource "azurerm_network_security_rule" "rules" {
  for_each                    = { for rule in local.all_security_rules : rule.name => rule }
  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  description                 = each.value.description
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
}

# =========================================
# OUTPUTS
# =========================================

output "nsg_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.main.id
}

output "nsg_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.main.name
}

output "security_rules" {
  description = "Map of security rule names to their IDs"
  value       = { for name, rule in azurerm_network_security_rule.rules : name => rule.id }
}

output "security_rules_summary" {
  description = "Summary of all security rules"
  value = [
    for rule in local.all_security_rules : {
      name      = rule.name
      priority  = rule.priority
      direction = rule.direction
      access    = rule.access
      protocol  = rule.protocol
      port      = rule.destination_port_range
    }
  ]
}
