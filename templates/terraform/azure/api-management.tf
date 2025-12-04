# =========================================
# Azure API Management - Terraform Template
# =========================================
# This template creates API Management with:
# - Configurable SKU (Developer, Basic, Standard, Premium, Consumption)
# - Publisher information
# - Custom domain support
# - Virtual network integration
# - Named values and products
# - API and operations
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

variable "apim_name" {
  description = "Name of the API Management service"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,49}$", var.apim_name))
    error_message = "APIM name must start with a letter, be 1-50 characters, and contain only letters, numbers, and hyphens"
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
  description = "SKU for API Management (Developer_1, Basic_1, Standard_1, Premium_1, Consumption_0)"
  type        = string
  default     = "Developer_1"

  validation {
    condition     = can(regex("^(Developer|Basic|Standard|Premium|Consumption)_[0-9]+$", var.sku_name))
    error_message = "SKU name must be in format: {Tier}_{Capacity} (e.g., Developer_1, Premium_2)"
  }
}

variable "publisher_name" {
  description = "Publisher name for API Management"
  type        = string

  validation {
    condition     = length(var.publisher_name) > 0
    error_message = "Publisher name is required"
  }
}

variable "publisher_email" {
  description = "Publisher email for API Management"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.publisher_email))
    error_message = "Publisher email must be a valid email address"
  }
}

variable "notification_sender_email" {
  description = "Email address from which notifications will be sent"
  type        = string
  default     = ""
}

variable "enable_client_certificate" {
  description = "Enable client certificate negotiation"
  type        = bool
  default     = false
}

variable "gateway_disabled" {
  description = "Disable gateway in the region"
  type        = bool
  default     = false
}

variable "min_api_version" {
  description = "Minimum API version (e.g., 2021-08-01)"
  type        = string
  default     = ""
}

variable "enable_portal" {
  description = "Enable developer portal"
  type        = bool
  default     = true
}

variable "enable_management_endpoint" {
  description = "Enable management API endpoint"
  type        = bool
  default     = true
}

variable "public_ip_address_id" {
  description = "Public IP address ID for API Management (Premium SKU only)"
  type        = string
  default     = null
}

variable "virtual_network_type" {
  description = "Virtual network type (None, External, Internal)"
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "External", "Internal"], var.virtual_network_type)
    error_message = "Virtual network type must be None, External, or Internal"
  }
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (required if virtual_network_type is not None)"
  type        = string
  default     = null
}

variable "identity_type" {
  description = "Type of identity (SystemAssigned, UserAssigned, or None)"
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "None"], var.identity_type)
    error_message = "Identity type must be SystemAssigned, UserAssigned, or None"
  }
}

variable "named_values" {
  description = "Named values (key-value pairs) for API Management"
  type = map(object({
    value  = string
    secret = optional(bool, false)
  }))
  default = {}
}

variable "products" {
  description = "Products to create in API Management"
  type = list(object({
    product_id            = string
    display_name          = string
    description           = string
    terms                 = optional(string, "")
    subscription_required = optional(bool, true)
    approval_required     = optional(bool, false)
    subscriptions_limit   = optional(number, 1)
    published             = optional(bool, true)
  }))
  default = []
}

variable "policies_xml" {
  description = "Global policy XML content"
  type        = string
  default     = ""
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
      Template  = "api-management"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# API Management Service
resource "azurerm_api_management" "main" {
  name                          = var.apim_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku_name                      = var.sku_name
  publisher_name                = var.publisher_name
  publisher_email               = var.publisher_email
  notification_sender_email     = var.notification_sender_email != "" ? var.notification_sender_email : var.publisher_email
  client_certificate_enabled    = var.enable_client_certificate
  gateway_disabled              = var.gateway_disabled
  min_api_version               = var.min_api_version != "" ? var.min_api_version : null
  public_ip_address_id          = var.public_ip_address_id
  virtual_network_type          = var.virtual_network_type
  tags                          = local.common_tags

  dynamic "virtual_network_configuration" {
    for_each = var.virtual_network_type != "None" && var.subnet_id != null ? [1] : []
    content {
      subnet_id = var.subnet_id
    }
  }

  dynamic "identity" {
    for_each = var.identity_type != "None" ? [1] : []
    content {
      type = var.identity_type
    }
  }

  protocols {
    enable_http2 = true
  }

  security {
    enable_backend_ssl30  = false
    enable_backend_tls10  = false
    enable_backend_tls11  = false
    enable_frontend_ssl30 = false
    enable_frontend_tls10 = false
    enable_frontend_tls11 = false
  }
}

# Named Values
resource "azurerm_api_management_named_value" "values" {
  for_each            = var.named_values
  name                = each.key
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  display_name        = each.key
  value               = each.value.value
  secret              = each.value.secret
}

# Products
resource "azurerm_api_management_product" "products" {
  for_each              = { for product in var.products : product.product_id => product }
  product_id            = each.value.product_id
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = var.resource_group_name
  display_name          = each.value.display_name
  description           = each.value.description
  terms                 = each.value.terms
  subscription_required = each.value.subscription_required
  approval_required     = each.value.approval_required
  subscriptions_limit   = each.value.subscriptions_limit
  published             = each.value.published
}

# Global Policy
resource "azurerm_api_management_policy" "main" {
  count               = var.policies_xml != "" ? 1 : 0
  api_management_id   = azurerm_api_management.main.id
  xml_content         = var.policies_xml
}

# =========================================
# OUTPUTS
# =========================================

output "apim_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "apim_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "gateway_regional_url" {
  description = "Regional gateway URL"
  value       = azurerm_api_management.main.gateway_regional_url
}

output "portal_url" {
  description = "Developer portal URL"
  value       = azurerm_api_management.main.developer_portal_url
}

output "management_api_url" {
  description = "Management API URL"
  value       = azurerm_api_management.main.management_api_url
}

output "public_ip_addresses" {
  description = "Public IP addresses of the API Management service"
  value       = azurerm_api_management.main.public_ip_addresses
}

output "private_ip_addresses" {
  description = "Private IP addresses of the API Management service"
  value       = azurerm_api_management.main.private_ip_addresses
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity"
  value       = var.identity_type != "None" ? azurerm_api_management.main.identity[0].principal_id : null
}
