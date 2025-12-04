# =========================================
# Azure Function App - Terraform Template
# =========================================
# This template creates a Function App with:
# - App Service Plan with configurable SKU
# - Storage Account for function app storage
# - Function App with runtime configuration
# - Application Insights (optional)
# - Deployment slots support (optional)
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

variable "function_app_name" {
  description = "Name of the function app"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.function_app_name))
    error_message = "Function app name must be 2-60 characters, contain only letters, numbers, and hyphens"
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

variable "storage_account_name" {
  description = "Name of the storage account for function app (3-24 chars, lowercase, numbers only)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase letters/numbers only"
  }
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan"
  type        = string
  default     = ""
}

variable "create_new_app_service_plan" {
  description = "Create a new App Service Plan (true) or use existing (false)"
  type        = bool
  default     = true
}

variable "app_service_plan_id" {
  description = "ID of existing App Service Plan (required if create_new_app_service_plan is false)"
  type        = string
  default     = null
}

variable "sku_name" {
  description = "SKU for the App Service Plan - affects cost and features (Y1=Consumption/pay-per-execution, EP1-EP3=Elastic Premium with pre-warmed instances, P1v2-P3v2=Dedicated Premium for always-on workloads)"
  type        = string

  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.sku_name)
    error_message = "SKU must be Y1, EP1-EP3, or P1v2-P3v2"
  }
}

variable "os_type" {
  description = "Operating system type for the App Service Plan - affects runtime compatibility (Linux recommended for most scenarios, Windows for .NET Framework)"
  type        = string

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be Linux or Windows"
  }
}

variable "runtime_stack" {
  description = "Runtime stack for the function app - affects what language your functions are written in"
  type        = string

  validation {
    condition     = contains(["dotnet", "node", "python", "java", "powershell"], var.runtime_stack)
    error_message = "Runtime stack must be dotnet, node, python, java, or powershell"
  }
}

variable "runtime_version" {
  description = "Runtime version (e.g., '3.9' for Python, '18' for Node.js)"
  type        = string
  default     = "3.11"
}

variable "functions_extension_version" {
  description = "Azure Functions runtime version - affects features (~4 recommended for latest features)"
  type        = string

  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4"
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "app_insights_name" {
  description = "Name of Application Insights resource"
  type        = string
  default     = ""
}

variable "always_on" {
  description = "Keep function app always on (not applicable for Consumption plan)"
  type        = bool
  default     = false
}

variable "app_settings" {
  description = "Additional application settings as key-value pairs"
  type        = map(string)
  default     = {}
}

variable "enable_cors" {
  description = "Enable CORS configuration"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "enable_https_only" {
  description = "Only allow HTTPS traffic"
  type        = bool
  default     = true
}

variable "enable_public_network_access" {
  description = "Enable public network access"
  type        = bool
  default     = true
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
  storage_account_name_final = var.storage_account_name
  app_service_plan_name_final = var.create_new_app_service_plan ? (
    var.app_service_plan_name != "" ? var.app_service_plan_name : "${var.function_app_name}-plan"
  ) : ""
  app_insights_name_final = var.enable_application_insights ? (
    var.app_insights_name != "" ? var.app_insights_name : "${var.function_app_name}-insights"
  ) : ""

  # Runtime configuration
  site_config = {
    "dotnet"      = { use_dotnet_isolated = true, dotnet_version = var.runtime_version }
    "node"        = { node_version = var.runtime_version }
    "python"      = { python_version = var.runtime_version }
    "java"        = { java_version = var.runtime_version }
    "powershell"  = { powershell_core_version = var.runtime_version }
  }

  # App Service Plan SKU tier
  sku_tier = {
    "Y1"   = "Dynamic"
    "EP1"  = "ElasticPremium"
    "EP2"  = "ElasticPremium"
    "EP3"  = "ElasticPremium"
    "P1v2" = "PremiumV2"
    "P2v2" = "PremiumV2"
    "P3v2" = "PremiumV2"
  }

  # Base app settings
  base_app_settings = merge(
    {
      FUNCTIONS_EXTENSION_VERSION       = var.functions_extension_version
      FUNCTIONS_WORKER_RUNTIME          = var.runtime_stack
      WEBSITE_RUN_FROM_PACKAGE          = "1"
    },
    var.enable_application_insights ? {
      APPINSIGHTS_INSTRUMENTATIONKEY    = azurerm_application_insights.main[0].instrumentation_key
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main[0].connection_string
    } : {},
    var.app_settings
  )

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "function-app"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Storage Account for Function App
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name_final
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  https_traffic_only_enabled = true
  tags                     = local.common_tags
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  count               = var.create_new_app_service_plan ? 1 : 0
  name                = local.app_service_plan_name_final
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = var.os_type
  sku_name            = var.sku_name
  tags                = local.common_tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name_final
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  tags                = local.common_tags
}

# Linux Function App
resource "azurerm_linux_function_app" "main" {
  count                      = var.os_type == "Linux" ? 1 : 0
  name                       = var.function_app_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = var.create_new_app_service_plan ? azurerm_service_plan.main[0].id : var.app_service_plan_id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  https_only                 = var.enable_https_only
  public_network_access_enabled = var.enable_public_network_access
  tags                       = local.common_tags

  site_config {
    always_on = var.sku_name != "Y1" ? var.always_on : false

    dynamic "application_stack" {
      for_each = var.runtime_stack == "python" ? [1] : []
      content {
        python_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "node" ? [1] : []
      content {
        node_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "dotnet" ? [1] : []
      content {
        dotnet_version = var.runtime_version
        use_dotnet_isolated_runtime = true
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "java" ? [1] : []
      content {
        java_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "powershell" ? [1] : []
      content {
        powershell_core_version = var.runtime_version
      }
    }

    dynamic "cors" {
      for_each = var.enable_cors ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  app_settings = local.base_app_settings
}

# Windows Function App
resource "azurerm_windows_function_app" "main" {
  count                      = var.os_type == "Windows" ? 1 : 0
  name                       = var.function_app_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = var.create_new_app_service_plan ? azurerm_service_plan.main[0].id : var.app_service_plan_id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  https_only                 = var.enable_https_only
  public_network_access_enabled = var.enable_public_network_access
  tags                       = local.common_tags

  site_config {
    always_on = var.sku_name != "Y1" ? var.always_on : false

    dynamic "application_stack" {
      for_each = var.runtime_stack == "python" ? [1] : []
      content {
        python_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "node" ? [1] : []
      content {
        node_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "dotnet" ? [1] : []
      content {
        dotnet_version = var.runtime_version
        use_dotnet_isolated_runtime = true
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "java" ? [1] : []
      content {
        java_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "powershell" ? [1] : []
      content {
        powershell_core_version = var.runtime_version
      }
    }

    dynamic "cors" {
      for_each = var.enable_cors ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  app_settings = local.base_app_settings
}

# =========================================
# OUTPUTS
# =========================================

output "function_app_id" {
  description = "ID of the function app"
  value       = var.os_type == "Linux" ? azurerm_linux_function_app.main[0].id : azurerm_windows_function_app.main[0].id
}

output "function_app_name" {
  description = "Name of the function app"
  value       = var.function_app_name
}

output "function_app_default_hostname" {
  description = "Default hostname of the function app"
  value       = var.os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = var.create_new_app_service_plan ? azurerm_service_plan.main[0].id : var.app_service_plan_id
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}
