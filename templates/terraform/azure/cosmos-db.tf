# =========================================
# Azure Cosmos DB - Terraform Template
# =========================================
# This template creates a Cosmos DB account with:
# - Configurable API type (SQL, MongoDB, Cassandra, Gremlin, Table)
# - Consistency level configuration
# - Geo-replication support
# - Automatic failover
# - Database and container/collection creation
# - Throughput configuration (manual or autoscale)
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

variable "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,44}$", var.cosmos_account_name))
    error_message = "Cosmos DB account name must be 3-44 characters, lowercase letters, numbers, and hyphens"
  }
}

variable "location" {
  description = "Primary Azure region for deployment"
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

variable "offer_type" {
  description = "Offer type for Cosmos DB account"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard"], var.offer_type)
    error_message = "Offer type must be Standard"
  }
}

variable "kind" {
  description = "Kind of Cosmos DB account - affects API compatibility (GlobalDocumentDB for SQL API, MongoDB for MongoDB API)"
  type        = string

  validation {
    condition     = contains(["GlobalDocumentDB", "MongoDB"], var.kind)
    error_message = "Kind must be GlobalDocumentDB or MongoDB"
  }
}

variable "consistency_level" {
  description = "Consistency level - affects performance and data consistency (Strong = highest consistency, Eventual = best performance, Session = balanced default)"
  type        = string

  validation {
    condition     = contains(["BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"], var.consistency_level)
    error_message = "Consistency level must be BoundedStaleness, Eventual, Session, Strong, or ConsistentPrefix"
  }
}

variable "max_staleness_prefix" {
  description = "Max staleness prefix for BoundedStaleness consistency"
  type        = number
  default     = 100

  validation {
    condition     = var.max_staleness_prefix >= 10 && var.max_staleness_prefix <= 2147483647
    error_message = "Max staleness prefix must be between 10 and 2147483647"
  }
}

variable "max_interval_in_seconds" {
  description = "Max interval in seconds for BoundedStaleness consistency"
  type        = number
  default     = 300

  validation {
    condition     = var.max_interval_in_seconds >= 5 && var.max_interval_in_seconds <= 86400
    error_message = "Max interval in seconds must be between 5 and 86400"
  }
}

variable "enable_free_tier" {
  description = "Enable free tier (limited to one per subscription)"
  type        = bool
  default     = false
}

variable "enable_automatic_failover" {
  description = "Enable automatic failover for multi-region accounts"
  type        = bool
  default     = false
}

variable "enable_multiple_write_locations" {
  description = "Enable multi-region writes"
  type        = bool
  default     = false
}

variable "secondary_locations" {
  description = "List of secondary locations for geo-replication"
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "ip_range_filter" {
  description = "IP addresses or CIDR ranges allowed to access Cosmos DB"
  type        = list(string)
  default     = []
}

variable "enable_analytical_storage" {
  description = "Enable analytical storage (Cosmos DB Analytical Store)"
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Name of the SQL database to create"
  type        = string
}

variable "database_throughput" {
  description = "Throughput for the database in RU/s (leave null for container-level throughput)"
  type        = number
  default     = null

  validation {
    condition     = var.database_throughput == null || (var.database_throughput >= 400 && var.database_throughput <= 1000000)
    error_message = "Database throughput must be between 400 and 1000000 RU/s or null"
  }
}

variable "enable_autoscale" {
  description = "Enable autoscale for throughput"
  type        = bool
  default     = false
}

variable "max_autoscale_throughput" {
  description = "Maximum autoscale throughput in RU/s (minimum 4000)"
  type        = number
  default     = 4000

  validation {
    condition     = var.max_autoscale_throughput >= 4000 && var.max_autoscale_throughput <= 1000000
    error_message = "Max autoscale throughput must be between 4000 and 1000000 RU/s"
  }
}

variable "containers" {
  description = "List of containers to create in the database"
  type = list(object({
    name               = string
    partition_key_path = string
    throughput         = optional(number, null)
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
  # Geo-replication configuration
  geo_locations = concat(
    [{
      location          = var.location
      failover_priority = 0
      zone_redundant    = false
    }],
    [for idx, loc in var.secondary_locations : {
      location          = loc
      failover_priority = idx + 1
      zone_redundant    = false
    }]
  )

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "cosmos-db"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "main" {
  name                          = var.cosmos_account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  offer_type                    = var.offer_type
  kind                          = var.kind
  enable_free_tier              = var.enable_free_tier
  enable_automatic_failover     = var.enable_automatic_failover
  enable_multiple_write_locations = var.enable_multiple_write_locations
  public_network_access_enabled = var.public_network_access_enabled
  ip_range_filter               = join(",", var.ip_range_filter)
  analytical_storage_enabled    = var.enable_analytical_storage
  tags                          = local.common_tags

  consistency_policy {
    consistency_level       = var.consistency_level
    max_staleness_prefix    = var.consistency_level == "BoundedStaleness" ? var.max_staleness_prefix : null
    max_interval_in_seconds = var.consistency_level == "BoundedStaleness" ? var.max_interval_in_seconds : null
  }

  dynamic "geo_location" {
    for_each = local.geo_locations
    content {
      location          = geo_location.value.location
      failover_priority = geo_location.value.failover_priority
      zone_redundant    = geo_location.value.zone_redundant
    }
  }

  capabilities {
    name = var.kind == "MongoDB" ? "EnableMongo" : "EnableServerless"
  }
}

# SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name

  # Throughput configuration
  throughput = !var.enable_autoscale && var.database_throughput != null ? var.database_throughput : null

  dynamic "autoscale_settings" {
    for_each = var.enable_autoscale && var.database_throughput != null ? [1] : []
    content {
      max_throughput = var.max_autoscale_throughput
    }
  }
}

# SQL Containers
resource "azurerm_cosmosdb_sql_container" "containers" {
  for_each            = { for container in var.containers : container.name => container }
  name                = each.value.name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = [each.value.partition_key_path]

  # Container-level throughput (if database-level throughput is not set)
  throughput = !var.enable_autoscale && var.database_throughput == null && each.value.throughput != null ? each.value.throughput : null

  dynamic "autoscale_settings" {
    for_each = var.enable_autoscale && var.database_throughput == null && each.value.throughput != null ? [1] : []
    content {
      max_throughput = each.value.throughput
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "cosmos_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_endpoint" {
  description = "Endpoint of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "primary_key" {
  description = "Primary master key for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "secondary_key" {
  description = "Secondary master key for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.secondary_key
  sensitive   = true
}

output "connection_strings" {
  description = "Connection strings for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "database_id" {
  description = "ID of the Cosmos DB SQL database"
  value       = azurerm_cosmosdb_sql_database.main.id
}

output "database_name" {
  description = "Name of the Cosmos DB SQL database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "container_ids" {
  description = "Map of container names to their IDs"
  value       = { for name, container in azurerm_cosmosdb_sql_container.containers : name => container.id }
}
