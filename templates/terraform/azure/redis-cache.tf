# =========================================
# Azure Redis Cache - Terraform Template
# =========================================
# This template creates an Azure Cache for Redis with:
# - Multiple SKU options (Basic, Standard, Premium)
# - Redis configuration
# - Data persistence (Premium SKU)
# - Clustering (Premium SKU)
# - Virtual network integration (Premium SKU)
# - Firewall rules
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

variable "redis_name" {
  description = "Name of the Redis cache (globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,63}$", var.redis_name))
    error_message = "Redis name must be 1-63 characters, letters, numbers, and hyphens"
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

variable "capacity" {
  description = "Cache capacity - affects cost and memory size (0=250MB, 1=1GB, 2=2.5GB, 3=6GB, 4=13GB, 5=26GB, 6=53GB)"
  type        = number
  default     = 1

  validation {
    condition     = var.capacity >= 0 && var.capacity <= 6
    error_message = "Capacity must be between 0 and 6"
  }
}

variable "family" {
  description = "SKU family - must match sku_name (C for Basic/Standard, P for Premium)"
  type        = string

  validation {
    condition     = contains(["C", "P"], var.family)
    error_message = "Family must be C or P"
  }
}

variable "sku_name" {
  description = "SKU name - affects cost and features (Basic = no SLA, Standard = SLA with replication, Premium = SLA with clustering and persistence)"
  type        = string

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku_name)
    error_message = "SKU name must be Basic, Standard, or Premium"
  }
}

variable "enable_non_ssl_port" {
  description = "Enable non-SSL port (6379)"
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version - affects security (1.2 recommended for security compliance)"
  type        = string

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2"
  }
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "redis_version" {
  description = "Redis version - affects features (6 recommended for latest features and performance)"
  type        = string

  validation {
    condition     = contains(["4", "6"], var.redis_version)
    error_message = "Redis version must be 4 or 6"
  }
}

variable "shard_count" {
  description = "Number of shards (Premium SKU only, 1-10)"
  type        = number
  default     = 1

  validation {
    condition     = var.shard_count >= 1 && var.shard_count <= 10
    error_message = "Shard count must be between 1 and 10"
  }
}

variable "replicas_per_master" {
  description = "Number of replicas per master (Premium SKU only, 1-3)"
  type        = number
  default     = 1

  validation {
    condition     = var.replicas_per_master >= 1 && var.replicas_per_master <= 3
    error_message = "Replicas per master must be between 1 and 3"
  }
}

variable "enable_persistence" {
  description = "Enable Redis data persistence (Premium SKU only)"
  type        = bool
  default     = false
}

variable "rdb_backup_enabled" {
  description = "Enable RDB backup (requires Premium SKU)"
  type        = bool
  default     = false
}

variable "rdb_backup_frequency" {
  description = "RDB backup frequency in minutes (15, 30, 60, 360, 720, 1440)"
  type        = number
  default     = 60

  validation {
    condition     = contains([15, 30, 60, 360, 720, 1440], var.rdb_backup_frequency)
    error_message = "RDB backup frequency must be 15, 30, 60, 360, 720, or 1440 minutes"
  }
}

variable "rdb_backup_max_snapshot_count" {
  description = "Maximum number of RDB snapshots"
  type        = number
  default     = 1
}

variable "rdb_storage_connection_string" {
  description = "Storage account connection string for RDB backups (required if rdb_backup_enabled is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (Premium SKU only)"
  type        = string
  default     = null
}

variable "private_static_ip_address" {
  description = "Static private IP address for VNet integration"
  type        = string
  default     = null
}

variable "zones" {
  description = "List of availability zones (Premium SKU only)"
  type        = list(string)
  default     = []
}

variable "redis_configuration" {
  description = "Redis configuration settings"
  type        = map(string)
  default     = {}
}

variable "firewall_rules" {
  description = "Firewall rules for Redis"
  type = list(object({
    name             = string
    start_ip_address = string
    end_ip_address   = string
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
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "redis-cache"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

resource "azurerm_redis_cache" "main" {
  name                          = var.redis_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  capacity                      = var.capacity
  family                        = var.family
  sku_name                      = var.sku_name
  enable_non_ssl_port           = var.enable_non_ssl_port
  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = var.public_network_access_enabled
  redis_version                 = var.redis_version
  shard_count                   = var.sku_name == "Premium" ? var.shard_count : null
  replicas_per_master           = var.sku_name == "Premium" ? var.replicas_per_master : null
  subnet_id                     = var.sku_name == "Premium" && var.subnet_id != null ? var.subnet_id : null
  private_static_ip_address     = var.sku_name == "Premium" && var.private_static_ip_address != null ? var.private_static_ip_address : null
  zones                         = var.sku_name == "Premium" && length(var.zones) > 0 ? var.zones : null
  tags                          = local.common_tags

  redis_configuration {
    maxmemory_reserved              = lookup(var.redis_configuration, "maxmemory_reserved", null)
    maxmemory_delta                 = lookup(var.redis_configuration, "maxmemory_delta", null)
    maxmemory_policy                = lookup(var.redis_configuration, "maxmemory_policy", "volatile-lru")
    maxfragmentationmemory_reserved = lookup(var.redis_configuration, "maxfragmentationmemory_reserved", null)
    enable_authentication           = lookup(var.redis_configuration, "enable_authentication", "true") == "true"

    rdb_backup_enabled              = var.sku_name == "Premium" && var.rdb_backup_enabled
    rdb_backup_frequency            = var.sku_name == "Premium" && var.rdb_backup_enabled ? var.rdb_backup_frequency : null
    rdb_backup_max_snapshot_count   = var.sku_name == "Premium" && var.rdb_backup_enabled ? var.rdb_backup_max_snapshot_count : null
    rdb_storage_connection_string   = var.sku_name == "Premium" && var.rdb_backup_enabled ? var.rdb_storage_connection_string : null
  }
}

resource "azurerm_redis_firewall_rule" "rules" {
  for_each            = { for rule in var.firewall_rules : rule.name => rule }
  name                = each.value.name
  redis_cache_name    = azurerm_redis_cache.main.name
  resource_group_name = var.resource_group_name
  start_ip            = each.value.start_ip_address
  end_ip              = each.value.end_ip_address
}

# =========================================
# OUTPUTS
# =========================================

output "redis_id" {
  description = "ID of the Redis cache"
  value       = azurerm_redis_cache.main.id
}

output "redis_name" {
  description = "Name of the Redis cache"
  value       = azurerm_redis_cache.main.name
}

output "hostname" {
  description = "Hostname of the Redis cache"
  value       = azurerm_redis_cache.main.hostname
}

output "ssl_port" {
  description = "SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "port" {
  description = "Non-SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.port
}

output "primary_access_key" {
  description = "Primary access key"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "secondary_access_key" {
  description = "Secondary access key"
  value       = azurerm_redis_cache.main.secondary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "Primary connection string"
  value       = azurerm_redis_cache.main.primary_connection_string
  sensitive   = true
}

output "secondary_connection_string" {
  description = "Secondary connection string"
  value       = azurerm_redis_cache.main.secondary_connection_string
  sensitive   = true
}
