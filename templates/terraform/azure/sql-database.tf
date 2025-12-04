# =========================================
# Azure SQL Server & Database - Terraform Template
# =========================================
# This template creates SQL Server and Database with:
# - SQL Server with Azure AD authentication support
# - SQL Database with configurable SKU
# - Firewall rules configuration
# - Threat detection policy (optional)
# - Transparent data encryption
# - Backup retention configuration
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

variable "sql_server_name" {
  description = "Name of the SQL server"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.sql_server_name))
    error_message = "SQL server name must be 1-63 characters, lowercase letters, numbers, and hyphens"
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

variable "administrator_login" {
  description = "Administrator username for SQL server"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,127}$", var.administrator_login))
    error_message = "Administrator login must start with a letter and be 1-128 characters"
  }
}

variable "administrator_login_password" {
  description = "Administrator password for SQL server"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.administrator_login_password) >= 8 && length(var.administrator_login_password) <= 128
    error_message = "Password must be 8-128 characters long"
  }
}

variable "sql_server_version" {
  description = "Version of SQL server"
  type        = string
  default     = "12.0"

  validation {
    condition     = contains(["12.0"], var.sql_server_version)
    error_message = "SQL server version must be 12.0"
  }
}

variable "sql_database_name" {
  description = "Name of the SQL database"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.sql_database_name))
    error_message = "Database name must be 1-128 characters, letters, numbers, hyphens, and underscores"
  }
}

variable "sku_name" {
  description = "SKU for the SQL database - affects cost and performance (Basic for light workloads, S0-S12 for standard, P1-P15 for premium, GP_S_Gen5 for general purpose serverless)"
  type        = string

  validation {
    condition     = can(regex("^(Basic|S[0-9]|S1[0-2]|P[1-9]|P1[0-5]|GP_S_Gen5_[1-9][0-9]?|GP_Gen5_[1-9][0-9]?|BC_Gen5_[1-9][0-9]?)$", var.sku_name))
    error_message = "SKU must be a valid SQL Database SKU (Basic, S0-S12, P1-P15, GP_S_Gen5_X, GP_Gen5_X, or BC_Gen5_X)"
  }
}

variable "max_size_gb" {
  description = "Maximum size of the database in GB"
  type        = number
  default     = 2

  validation {
    condition     = var.max_size_gb >= 1 && var.max_size_gb <= 4096
    error_message = "Database size must be between 1 and 4096 GB"
  }
}

variable "collation" {
  description = "Collation for the database"
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "license_type" {
  description = "License type for the database - affects cost (LicenseIncluded = standard pricing, BasePrice = Azure Hybrid Benefit for cost savings with existing SQL licenses)"
  type        = string

  validation {
    condition     = contains(["LicenseIncluded", "BasePrice"], var.license_type)
    error_message = "License type must be LicenseIncluded or BasePrice"
  }
}

variable "read_scale" {
  description = "Enable read scale-out for the database"
  type        = bool
  default     = false
}

variable "zone_redundant" {
  description = "Enable zone redundancy for the database"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 7 and 35"
  }
}

variable "enable_transparent_data_encryption" {
  description = "Enable transparent data encryption"
  type        = bool
  default     = true
}

variable "enable_public_network_access" {
  description = "Enable public network access to SQL server"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for the SQL server - affects security (1.2 recommended for security compliance)"
  type        = string

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2"
  }
}

variable "enable_azure_services_access" {
  description = "Allow Azure services to access the SQL server"
  type        = bool
  default     = true
}

variable "firewall_rules" {
  description = "List of firewall rules"
  type = list(object({
    name             = string
    start_ip_address = string
    end_ip_address   = string
  }))
  default = []
}

variable "enable_threat_detection" {
  description = "Enable threat detection policy"
  type        = bool
  default     = false
}

variable "threat_detection_email_addresses" {
  description = "Email addresses for threat detection alerts"
  type        = list(string)
  default     = []
}

variable "storage_account_id" {
  description = "Storage account ID for threat detection logs (required if enable_threat_detection is true)"
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
  # Azure services firewall rule
  azure_services_rule = var.enable_azure_services_access ? [{
    name             = "AllowAzureServices"
    start_ip_address = "0.0.0.0"
    end_ip_address   = "0.0.0.0"
  }] : []

  # Combined firewall rules
  all_firewall_rules = concat(local.azure_services_rule, var.firewall_rules)

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "sql-database"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = var.sql_server_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  version                      = var.sql_server_version
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password
  minimum_tls_version          = var.minimum_tls_version
  public_network_access_enabled = var.enable_public_network_access
  tags                         = local.common_tags
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  name           = var.sql_database_name
  server_id      = azurerm_mssql_server.main.id
  collation      = var.collation
  license_type   = var.license_type
  max_size_gb    = var.max_size_gb
  sku_name       = var.sku_name
  zone_redundant = var.zone_redundant
  read_scale     = var.read_scale
  tags           = local.common_tags

  short_term_retention_policy {
    retention_days = var.backup_retention_days
  }

  transparent_data_encryption_enabled = var.enable_transparent_data_encryption
}

# Firewall Rules
resource "azurerm_mssql_firewall_rule" "rules" {
  for_each         = { for rule in local.all_firewall_rules : rule.name => rule }
  name             = each.value.name
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

# Threat Detection Policy
resource "azurerm_mssql_server_security_alert_policy" "main" {
  count                      = var.enable_threat_detection ? 1 : 0
  resource_group_name        = var.resource_group_name
  server_name                = azurerm_mssql_server.main.name
  state                      = "Enabled"
  email_account_admins       = true
  email_addresses            = var.threat_detection_email_addresses
  retention_days             = 30
  storage_endpoint           = var.storage_account_id != null ? "https://${data.azurerm_storage_account.threat_detection[0].name}.blob.core.windows.net/" : null
  storage_account_access_key = var.storage_account_id != null ? data.azurerm_storage_account.threat_detection[0].primary_access_key : null
}

# Data source for storage account (if threat detection enabled)
data "azurerm_storage_account" "threat_detection" {
  count               = var.enable_threat_detection && var.storage_account_id != null ? 1 : 0
  name                = element(split("/", var.storage_account_id), length(split("/", var.storage_account_id)) - 1)
  resource_group_name = var.resource_group_name
}

# =========================================
# OUTPUTS
# =========================================

output "sql_server_id" {
  description = "ID of the SQL server"
  value       = azurerm_mssql_server.main.id
}

output "sql_server_name" {
  description = "Name of the SQL server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_id" {
  description = "ID of the SQL database"
  value       = azurerm_mssql_database.main.id
}

output "sql_database_name" {
  description = "Name of the SQL database"
  value       = azurerm_mssql_database.main.name
}

output "connection_string" {
  description = "Connection string for the database (without password)"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.administrator_login};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = true
}
