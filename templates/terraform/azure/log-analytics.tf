# =========================================
# Azure Log Analytics Workspace - Terraform Template
# =========================================
# This template creates a Log Analytics Workspace with:
# - Configurable SKU and retention
# - Data export rules
# - Saved searches and solutions
# - Integration with monitoring resources
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

variable "workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.workspace_name))
    error_message = "Workspace name must be 4-63 characters, letters, numbers, and hyphens"
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
  description = "SKU for the workspace (Free, PerGB2018, PerNode, Premium, Standalone)"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "PerGB2018", "PerNode", "Premium", "Standalone"], var.sku)
    error_message = "SKU must be Free, PerGB2018, PerNode, Premium, or Standalone"
  }
}

variable "retention_in_days" {
  description = "Data retention period in days (30-730 for paid SKUs, 7 for Free)"
  type        = number
  default     = 30

  validation {
    condition     = (var.retention_in_days >= 7 && var.retention_in_days <= 730)
    error_message = "Retention days must be between 7 and 730"
  }
}

variable "daily_quota_gb" {
  description = "Daily ingestion limit in GB (-1 for unlimited)"
  type        = number
  default     = -1

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb >= 0.023
    error_message = "Daily quota must be -1 (unlimited) or >= 0.023 GB"
  }
}

variable "internet_ingestion_enabled" {
  description = "Enable internet ingestion"
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "Enable internet query"
  type        = bool
  default     = true
}

variable "enable_solutions" {
  description = "Enable Log Analytics solutions"
  type        = bool
  default     = true
}

variable "solutions" {
  description = "List of solutions to enable"
  type        = list(string)
  default     = ["ContainerInsights", "Security", "Updates", "AzureActivity"]

  validation {
    condition = alltrue([
      for solution in var.solutions :
      contains([
        "ContainerInsights",
        "Security",
        "Updates",
        "AzureActivity",
        "ChangeTracking",
        "ServiceMap",
        "SQLAdvancedThreatProtection",
        "SQLVulnerabilityAssessment",
        "SQLAssessment",
        "AgentHealthAssessment",
        "DnsAnalytics",
        "ApplicationInsights"
      ], solution)
    ])
    error_message = "Invalid solution name"
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
  # Solution publisher mapping
  solution_publisher = {
    ContainerInsights            = "Microsoft"
    Security                     = "Microsoft"
    Updates                      = "Microsoft"
    AzureActivity                = "Microsoft"
    ChangeTracking               = "Microsoft"
    ServiceMap                   = "Microsoft"
    SQLAdvancedThreatProtection  = "Microsoft"
    SQLVulnerabilityAssessment   = "Microsoft"
    SQLAssessment                = "Microsoft"
    AgentHealthAssessment        = "Microsoft"
    DnsAnalytics                 = "Microsoft"
    ApplicationInsights          = "Microsoft"
  }

  # Solution product mapping
  solution_product = {
    ContainerInsights            = "OMSGallery/ContainerInsights"
    Security                     = "OMSGallery/Security"
    Updates                      = "OMSGallery/Updates"
    AzureActivity                = "OMSGallery/AzureActivity"
    ChangeTracking               = "OMSGallery/ChangeTracking"
    ServiceMap                   = "OMSGallery/ServiceMap"
    SQLAdvancedThreatProtection  = "OMSGallery/SQLAdvancedThreatProtection"
    SQLVulnerabilityAssessment   = "OMSGallery/SQLVulnerabilityAssessment"
    SQLAssessment                = "OMSGallery/SQLAssessment"
    AgentHealthAssessment        = "OMSGallery/AgentHealthAssessment"
    DnsAnalytics                 = "OMSGallery/DnsAnalytics"
    ApplicationInsights          = "OMSGallery/ApplicationInsights"
  }

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "log-analytics"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                       = var.workspace_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  sku                        = var.sku
  retention_in_days          = var.retention_in_days
  daily_quota_gb             = var.daily_quota_gb
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled
  tags                       = local.common_tags
}

# Log Analytics Solutions
resource "azurerm_log_analytics_solution" "solutions" {
  for_each = var.enable_solutions ? toset(var.solutions) : toset([])

  solution_name         = each.key
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  tags                  = local.common_tags

  plan {
    publisher = local.solution_publisher[each.key]
    product   = local.solution_product[each.key]
  }
}

# =========================================
# OUTPUTS
# =========================================

output "workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "workspace_customer_id" {
  description = "Workspace (customer) ID for Log Analytics"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "primary_shared_key" {
  description = "Primary shared key for the workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "secondary_shared_key" {
  description = "Secondary shared key for the workspace"
  value       = azurerm_log_analytics_workspace.main.secondary_shared_key
  sensitive   = true
}

output "solutions_enabled" {
  description = "List of enabled solutions"
  value       = var.enable_solutions ? var.solutions : []
}
