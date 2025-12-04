# =========================================
# Azure Service Bus - Terraform Template
# =========================================
# This template creates a Service Bus namespace with:
# - Configurable SKU (Basic, Standard, Premium)
# - Queues and Topics with subscriptions
# - Authorization rules
# - Network rules and private endpoints
# - Geo-disaster recovery (Premium SKU)
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

variable "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace (6-50 chars, alphanumeric and hyphens)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$", var.servicebus_namespace_name))
    error_message = "Service Bus namespace name must be 6-50 characters, start with letter, end with alphanumeric"
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
  description = "SKU for the Service Bus namespace - affects cost and features (Basic=queues only, Standard=adds topics, Premium=adds dedicated capacity and VNet integration)"
  type        = string

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium"
  }
}

variable "capacity" {
  description = "Messaging units for Premium SKU (1, 2, 4, 8, 16)"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 4, 8, 16], var.capacity)
    error_message = "Capacity must be 1, 2, 4, 8, or 16"
  }
}

variable "zone_redundant" {
  description = "Enable zone redundancy (Premium SKU only)"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version - affects security (1.2 recommended for security compliance)"
  type        = string

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2"
  }
}

variable "local_auth_enabled" {
  description = "Enable local authentication (SAS keys)"
  type        = bool
  default     = true
}

variable "queues" {
  description = "List of queues to create"
  type = list(object({
    name                                 = string
    max_size_in_megabytes                = optional(number, 1024)
    default_message_ttl                  = optional(string, "P14D")
    lock_duration                        = optional(string, "PT1M")
    max_delivery_count                   = optional(number, 10)
    dead_lettering_on_message_expiration = optional(bool, false)
    enable_partitioning                  = optional(bool, false)
    enable_express                       = optional(bool, false)
    enable_sessions                      = optional(bool, false)
    duplicate_detection_history_time_window = optional(string, "PT10M")
  }))
  default = []
}

variable "topics" {
  description = "List of topics to create"
  type = list(object({
    name                  = string
    max_size_in_megabytes = optional(number, 1024)
    default_message_ttl   = optional(string, "P14D")
    enable_partitioning   = optional(bool, false)
    enable_express        = optional(bool, false)
    support_ordering      = optional(bool, false)
    duplicate_detection_history_time_window = optional(string, "PT10M")
    subscriptions = optional(list(object({
      name                                 = string
      max_delivery_count                   = optional(number, 10)
      lock_duration                        = optional(string, "PT1M")
      default_message_ttl                  = optional(string, "P14D")
      dead_lettering_on_message_expiration = optional(bool, false)
      dead_lettering_on_filter_evaluation_error = optional(bool, true)
      enable_sessions                      = optional(bool, false)
    })), [])
  }))
  default = []
}

variable "authorization_rules" {
  description = "Authorization rules for the namespace"
  type = list(object({
    name   = string
    listen = bool
    send   = bool
    manage = bool
  }))
  default = []
}

variable "network_rule_set_default_action" {
  description = "Default action for network rules (Allow or Deny)"
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rule_set_default_action)
    error_message = "Network rule set default action must be Allow or Deny"
  }
}

variable "ip_rules" {
  description = "List of IP addresses or CIDR ranges allowed to access Service Bus"
  type        = list(string)
  default     = []
}

variable "virtual_network_rules" {
  description = "List of subnet IDs allowed to access Service Bus"
  type        = list(string)
  default     = []
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
      Template  = "service-bus"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Service Bus Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                          = var.servicebus_namespace_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku
  capacity                      = var.sku == "Premium" ? var.capacity : 0
  zone_redundant                = var.sku == "Premium" ? var.zone_redundant : false
  public_network_access_enabled = var.public_network_access_enabled
  minimum_tls_version           = var.minimum_tls_version
  local_auth_enabled            = var.local_auth_enabled
  tags                          = local.common_tags
}

# Network Rules
resource "azurerm_servicebus_namespace_network_rule_set" "main" {
  count                        = length(var.ip_rules) > 0 || length(var.virtual_network_rules) > 0 ? 1 : 0
  namespace_id                 = azurerm_servicebus_namespace.main.id
  default_action               = var.network_rule_set_default_action
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "network_rules" {
    for_each = var.virtual_network_rules
    content {
      subnet_id                            = network_rules.value
      ignore_missing_vnet_service_endpoint = false
    }
  }

  ip_rules = var.ip_rules
}

# Authorization Rules
resource "azurerm_servicebus_namespace_authorization_rule" "rules" {
  for_each     = { for rule in var.authorization_rules : rule.name => rule }
  name         = each.value.name
  namespace_id = azurerm_servicebus_namespace.main.id
  listen       = each.value.listen
  send         = each.value.send
  manage       = each.value.manage
}

# Queues
resource "azurerm_servicebus_queue" "queues" {
  for_each                                 = { for queue in var.queues : queue.name => queue }
  name                                     = each.value.name
  namespace_id                             = azurerm_servicebus_namespace.main.id
  max_size_in_megabytes                    = each.value.max_size_in_megabytes
  default_message_ttl                      = each.value.default_message_ttl
  lock_duration                            = each.value.lock_duration
  max_delivery_count                       = each.value.max_delivery_count
  dead_lettering_on_message_expiration     = each.value.dead_lettering_on_message_expiration
  enable_partitioning                      = var.sku != "Premium" ? each.value.enable_partitioning : false
  enable_express                           = var.sku == "Standard" ? each.value.enable_express : false
  requires_session                         = each.value.enable_sessions
  duplicate_detection_history_time_window  = each.value.duplicate_detection_history_time_window
}

# Topics
resource "azurerm_servicebus_topic" "topics" {
  for_each                                = { for topic in var.topics : topic.name => topic }
  name                                    = each.value.name
  namespace_id                            = azurerm_servicebus_namespace.main.id
  max_size_in_megabytes                   = each.value.max_size_in_megabytes
  default_message_ttl                     = each.value.default_message_ttl
  enable_partitioning                     = var.sku != "Premium" ? each.value.enable_partitioning : false
  enable_express                          = var.sku == "Standard" ? each.value.enable_express : false
  support_ordering                        = each.value.support_ordering
  duplicate_detection_history_time_window = each.value.duplicate_detection_history_time_window
}

# Topic Subscriptions
resource "azurerm_servicebus_subscription" "subscriptions" {
  for_each = merge([
    for topic in var.topics : {
      for sub in topic.subscriptions :
      "${topic.name}-${sub.name}" => merge(sub, { topic_name = topic.name })
    }
  ]...)

  name                                     = each.value.name
  topic_id                                 = azurerm_servicebus_topic.topics[each.value.topic_name].id
  max_delivery_count                       = each.value.max_delivery_count
  lock_duration                            = each.value.lock_duration
  default_message_ttl                      = each.value.default_message_ttl
  dead_lettering_on_message_expiration     = each.value.dead_lettering_on_message_expiration
  dead_lettering_on_filter_evaluation_error = each.value.dead_lettering_on_filter_evaluation_error
  requires_session                         = each.value.enable_sessions
}

# =========================================
# OUTPUTS
# =========================================

output "namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "endpoint" {
  description = "Endpoint URL for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.endpoint
}

output "default_primary_connection_string" {
  description = "Primary connection string for the namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "default_primary_key" {
  description = "Primary key for the namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_key
  sensitive   = true
}

output "queue_ids" {
  description = "Map of queue names to their IDs"
  value       = { for name, queue in azurerm_servicebus_queue.queues : name => queue.id }
}

output "topic_ids" {
  description = "Map of topic names to their IDs"
  value       = { for name, topic in azurerm_servicebus_topic.topics : name => topic.id }
}
