# =========================================
# Azure Load Balancer - Terraform Template
# =========================================
# This template creates a Load Balancer with:
# - Public or Internal Load Balancer
# - Frontend IP configuration
# - Backend address pools
# - Health probes
# - Load balancing rules
# - Inbound NAT rules (optional)
# - Outbound rules (optional)
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

variable "lb_name" {
  description = "Name of the load balancer"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]{1,80}$", var.lb_name))
    error_message = "Load balancer name must be 1-80 characters"
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
  description = "SKU for the load balancer - affects features and cost (Basic=limited features, Standard=recommended with HA ports and availability zones)"
  type        = string

  validation {
    condition     = contains(["Basic", "Standard"], var.sku)
    error_message = "SKU must be Basic or Standard"
  }
}

variable "lb_type" {
  description = "Type of load balancer (Public=internet-facing, Internal=private network only)"
  type        = string

  validation {
    condition     = contains(["Public", "Internal"], var.lb_type)
    error_message = "Load balancer type must be Public or Internal"
  }
}

# Public Frontend Configuration
variable "create_public_ip" {
  description = "Create a new public IP for the load balancer"
  type        = bool
  default     = true
}

variable "public_ip_name" {
  description = "Name of the public IP (if creating new)"
  type        = string
  default     = ""
}

variable "public_ip_id" {
  description = "ID of existing public IP (if not creating new)"
  type        = string
  default     = null
}

variable "public_ip_allocation_method" {
  description = "Allocation method for public IP (Static or Dynamic)"
  type        = string
  default     = "Static"
}

variable "public_ip_sku" {
  description = "SKU for public IP (Basic or Standard)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard"], var.public_ip_sku)
    error_message = "Public IP SKU must be Basic or Standard"
  }
}

# Internal Frontend Configuration
variable "subnet_id" {
  description = "Subnet ID for internal load balancer (required if lb_type is Internal)"
  type        = string
  default     = null
}

variable "private_ip_address" {
  description = "Private IP address for internal load balancer (leave empty for dynamic)"
  type        = string
  default     = ""
}

variable "private_ip_address_allocation" {
  description = "Private IP allocation method (Static or Dynamic)"
  type        = string
  default     = "Dynamic"
}

# Backend Pools
variable "backend_pool_names" {
  description = "List of backend pool names to create"
  type        = list(string)
  default     = ["backend-pool"]
}

# Health Probes
variable "health_probes" {
  description = "List of health probes"
  type = list(object({
    name                = string
    protocol            = string
    port                = number
    request_path        = optional(string, "/")
    interval_in_seconds = optional(number, 15)
    number_of_probes    = optional(number, 2)
  }))
  default = [
    {
      name                = "http-probe"
      protocol            = "Http"
      port                = 80
      request_path        = "/"
      interval_in_seconds = 15
      number_of_probes    = 2
    }
  ]
}

# Load Balancing Rules
variable "lb_rules" {
  description = "List of load balancing rules"
  type = list(object({
    name                           = string
    frontend_port                  = number
    backend_port                   = number
    protocol                       = string
    probe_name                     = string
    backend_address_pool_name      = optional(string, "backend-pool")
    enable_floating_ip             = optional(bool, false)
    idle_timeout_in_minutes        = optional(number, 4)
    load_distribution              = optional(string, "Default")
    disable_outbound_snat          = optional(bool, false)
    enable_tcp_reset               = optional(bool, false)
  }))
  default = [
    {
      name          = "http-rule"
      frontend_port = 80
      backend_port  = 80
      protocol      = "Tcp"
      probe_name    = "http-probe"
    }
  ]
}

# Inbound NAT Rules
variable "inbound_nat_rules" {
  description = "List of inbound NAT rules"
  type = list(object({
    name                    = string
    protocol                = string
    frontend_port           = number
    backend_port            = number
    idle_timeout_in_minutes = optional(number, 4)
    enable_floating_ip      = optional(bool, false)
    enable_tcp_reset        = optional(bool, false)
  }))
  default = []
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
  # Resource naming
  public_ip_name_final = var.create_public_ip && var.lb_type == "Public" ? (
    var.public_ip_name != "" ? var.public_ip_name : "${var.lb_name}-pip"
  ) : ""

  # Frontend IP configuration
  frontend_ip_config_name = var.lb_type == "Public" ? "PublicIPAddress" : "PrivateIPAddress"

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "load-balancer"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Public IP (for Public Load Balancer)
resource "azurerm_public_ip" "lb" {
  count               = var.lb_type == "Public" && var.create_public_ip ? 1 : 0
  name                = local.public_ip_name_final
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  tags                = local.common_tags
}

# Load Balancer
resource "azurerm_lb" "main" {
  name                = var.lb_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = local.common_tags

  # Public Frontend IP Configuration
  dynamic "frontend_ip_configuration" {
    for_each = var.lb_type == "Public" ? [1] : []
    content {
      name                 = local.frontend_ip_config_name
      public_ip_address_id = var.create_public_ip ? azurerm_public_ip.lb[0].id : var.public_ip_id
    }
  }

  # Internal Frontend IP Configuration
  dynamic "frontend_ip_configuration" {
    for_each = var.lb_type == "Internal" ? [1] : []
    content {
      name                          = local.frontend_ip_config_name
      subnet_id                     = var.subnet_id
      private_ip_address            = var.private_ip_address != "" ? var.private_ip_address : null
      private_ip_address_allocation = var.private_ip_address_allocation
    }
  }
}

# Backend Address Pools
resource "azurerm_lb_backend_address_pool" "pools" {
  for_each        = toset(var.backend_pool_names)
  loadbalancer_id = azurerm_lb.main.id
  name            = each.key
}

# Health Probes
resource "azurerm_lb_probe" "probes" {
  for_each            = { for probe in var.health_probes : probe.name => probe }
  loadbalancer_id     = azurerm_lb.main.id
  name                = each.value.name
  protocol            = each.value.protocol
  port                = each.value.port
  request_path        = each.value.protocol == "Http" || each.value.protocol == "Https" ? each.value.request_path : null
  interval_in_seconds = each.value.interval_in_seconds
  number_of_probes    = each.value.number_of_probes
}

# Load Balancing Rules
resource "azurerm_lb_rule" "rules" {
  for_each                       = { for rule in var.lb_rules : rule.name => rule }
  loadbalancer_id                = azurerm_lb.main.id
  name                           = each.value.name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = local.frontend_ip_config_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pools[each.value.backend_address_pool_name].id]
  probe_id                       = azurerm_lb_probe.probes[each.value.probe_name].id
  enable_floating_ip             = each.value.enable_floating_ip
  idle_timeout_in_minutes        = each.value.idle_timeout_in_minutes
  load_distribution              = each.value.load_distribution
  disable_outbound_snat          = each.value.disable_outbound_snat
  enable_tcp_reset               = each.value.enable_tcp_reset
}

# Inbound NAT Rules
resource "azurerm_lb_nat_rule" "nat_rules" {
  for_each                       = { for rule in var.inbound_nat_rules : rule.name => rule }
  resource_group_name            = var.resource_group_name
  loadbalancer_id                = azurerm_lb.main.id
  name                           = each.value.name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = local.frontend_ip_config_name
  idle_timeout_in_minutes        = each.value.idle_timeout_in_minutes
  enable_floating_ip             = each.value.enable_floating_ip
  enable_tcp_reset               = each.value.enable_tcp_reset
}

# =========================================
# OUTPUTS
# =========================================

output "lb_id" {
  description = "ID of the load balancer"
  value       = azurerm_lb.main.id
}

output "lb_name" {
  description = "Name of the load balancer"
  value       = azurerm_lb.main.name
}

output "public_ip_address" {
  description = "Public IP address of the load balancer (if applicable)"
  value       = var.lb_type == "Public" && var.create_public_ip ? azurerm_public_ip.lb[0].ip_address : null
}

output "private_ip_address" {
  description = "Private IP address of the load balancer (if applicable)"
  value       = var.lb_type == "Internal" ? azurerm_lb.main.private_ip_address : null
}

output "frontend_ip_configuration_id" {
  description = "ID of the frontend IP configuration"
  value       = azurerm_lb.main.frontend_ip_configuration[0].id
}

output "backend_pool_ids" {
  description = "Map of backend pool names to their IDs"
  value       = { for name, pool in azurerm_lb_backend_address_pool.pools : name => pool.id }
}
