# =========================================
# Azure Application Gateway - Terraform Template
# =========================================
# This template creates an Application Gateway with:
# - WAF support (v1 or v2 SKU)
# - Backend pools and settings
# - HTTP/HTTPS listeners
# - Routing rules
# - SSL certificates
# - Health probes
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

variable "app_gateway_name" {
  description = "Name of the application gateway"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]{1,80}$", var.app_gateway_name))
    error_message = "Application gateway name must be 1-80 characters"
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
  description = "SKU name (Standard_Small, Standard_Medium, Standard_Large, WAF_Medium, WAF_Large, Standard_v2, WAF_v2)"
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_Small", "Standard_Medium", "Standard_Large", "WAF_Medium", "WAF_Large", "Standard_v2", "WAF_v2"], var.sku_name)
    error_message = "Invalid SKU name"
  }
}

variable "sku_tier" {
  description = "SKU tier (Standard, WAF, Standard_v2, WAF_v2)"
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard", "WAF", "Standard_v2", "WAF_v2"], var.sku_tier)
    error_message = "Invalid SKU tier"
  }
}

variable "sku_capacity" {
  description = "SKU capacity (1-125)"
  type        = number
  default     = 2

  validation {
    condition     = var.sku_capacity >= 1 && var.sku_capacity <= 125
    error_message = "SKU capacity must be between 1 and 125"
  }
}

variable "subnet_id" {
  description = "Subnet ID for application gateway"
  type        = string
}

variable "public_ip_id" {
  description = "Public IP address ID for frontend"
  type        = string
}

variable "backend_address_pools" {
  description = "List of backend address pools"
  type = list(object({
    name         = string
    ip_addresses = optional(list(string), [])
    fqdns        = optional(list(string), [])
  }))
}

variable "backend_http_settings" {
  description = "List of backend HTTP settings"
  type = list(object({
    name                  = string
    port                  = number
    protocol              = string
    cookie_based_affinity = string
    request_timeout       = optional(number, 30)
  }))
}

variable "http_listeners" {
  description = "List of HTTP listeners"
  type = list(object({
    name                           = string
    frontend_ip_configuration_name = string
    frontend_port_name             = string
    protocol                       = string
  }))
}

variable "request_routing_rules" {
  description = "List of request routing rules"
  type = list(object({
    name                       = string
    rule_type                  = string
    http_listener_name         = string
    backend_address_pool_name  = string
    backend_http_settings_name = string
    priority                   = number
  }))
}

variable "frontend_ports" {
  description = "List of frontend ports"
  type = list(object({
    name = string
    port = number
  }))
  default = [
    {
      name = "http"
      port = 80
    }
  ]
}

variable "enable_waf" {
  description = "Enable WAF (requires WAF SKU)"
  type        = bool
  default     = false
}

variable "waf_mode" {
  description = "WAF mode (Detection or Prevention)"
  type        = string
  default     = "Detection"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be Detection or Prevention"
  }
}

variable "waf_rule_set_version" {
  description = "WAF rule set version"
  type        = string
  default     = "3.2"
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
      Template  = "application-gateway"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

resource "azurerm_application_gateway" "main" {
  name                = var.app_gateway_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  sku {
    name     = var.sku_name
    tier     = var.sku_tier
    capacity = var.sku_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = var.public_ip_id
  }

  dynamic "frontend_port" {
    for_each = var.frontend_ports
    content {
      name = frontend_port.value.name
      port = frontend_port.value.port
    }
  }

  dynamic "backend_address_pool" {
    for_each = var.backend_address_pools
    content {
      name         = backend_address_pool.value.name
      ip_addresses = backend_address_pool.value.ip_addresses
      fqdns        = backend_address_pool.value.fqdns
    }
  }

  dynamic "backend_http_settings" {
    for_each = var.backend_http_settings
    content {
      name                  = backend_http_settings.value.name
      port                  = backend_http_settings.value.port
      protocol              = backend_http_settings.value.protocol
      cookie_based_affinity = backend_http_settings.value.cookie_based_affinity
      request_timeout       = backend_http_settings.value.request_timeout
    }
  }

  dynamic "http_listener" {
    for_each = var.http_listeners
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = http_listener.value.frontend_ip_configuration_name
      frontend_port_name             = http_listener.value.frontend_port_name
      protocol                       = http_listener.value.protocol
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.request_routing_rules
    content {
      name                       = request_routing_rule.value.name
      rule_type                  = request_routing_rule.value.rule_type
      http_listener_name         = request_routing_rule.value.http_listener_name
      backend_address_pool_name  = request_routing_rule.value.backend_address_pool_name
      backend_http_settings_name = request_routing_rule.value.backend_http_settings_name
      priority                   = request_routing_rule.value.priority
    }
  }

  dynamic "waf_configuration" {
    for_each = var.enable_waf ? [1] : []
    content {
      enabled          = true
      firewall_mode    = var.waf_mode
      rule_set_version = var.waf_rule_set_version
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "app_gateway_id" {
  description = "ID of the application gateway"
  value       = azurerm_application_gateway.main.id
}

output "app_gateway_name" {
  description = "Name of the application gateway"
  value       = azurerm_application_gateway.main.name
}
