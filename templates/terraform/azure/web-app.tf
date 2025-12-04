# =========================================
# Azure Web App - Terraform Template
# =========================================
# This template creates a Web App with:
# - App Service Plan with configurable SKU
# - Linux or Windows Web App
# - Application Insights (optional)
# - Custom domain and SSL support (optional)
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

variable "web_app_name" {
  description = "Name of the web app"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.web_app_name))
    error_message = "Web app name must be 2-60 characters, contain only letters, numbers, and hyphens"
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
  description = "SKU for the App Service Plan - affects cost and performance (F1/D1=Free/Shared, B1-B3=Basic, S1-S3=Standard with slots, P1v2-P3v3=Premium with better performance)"
  type        = string

  validation {
    condition     = can(regex("^(B[1-3]|S[1-3]|P[1-3]v[2-3]|F1|D1)$", var.sku_name))
    error_message = "SKU must be a valid App Service Plan SKU (B1-B3, S1-S3, P1v2-P3v3, F1, D1)"
  }
}

variable "os_type" {
  description = "Operating system type for the App Service Plan - affects runtime compatibility (Linux recommended for cost and performance, Windows for ASP.NET Framework)"
  type        = string

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be Linux or Windows"
  }
}

variable "runtime_stack" {
  description = "Runtime stack for the web app - affects what language your application is written in"
  type        = string

  validation {
    condition     = contains(["DOTNETCORE", "NODE", "PYTHON", "PHP", "JAVA", "RUBY", "GO"], var.runtime_stack)
    error_message = "Runtime stack must be DOTNETCORE, NODE, PYTHON, PHP, JAVA, RUBY, or GO"
  }
}

variable "runtime_version" {
  description = "Runtime version (e.g., '3.11' for Python, '18-lts' for Node.js, '8.0' for .NET)"
  type        = string
  default     = "3.11"
}

variable "always_on" {
  description = "Keep web app always on (not available for Free tier)"
  type        = bool
  default     = true
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

variable "app_settings" {
  description = "Additional application settings as key-value pairs"
  type        = map(string)
  default     = {}
}

variable "connection_strings" {
  description = "Connection strings for the web app"
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default = []
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

variable "minimum_tls_version" {
  description = "Minimum TLS version - affects security (1.2 or 1.3 recommended for security compliance)"
  type        = string

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, 1.2, or 1.3"
  }
}

variable "enable_public_network_access" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "enable_vnet_integration" {
  description = "Enable VNet integration"
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (required if enable_vnet_integration is true)"
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
  # Resource naming
  app_service_plan_name_final = var.create_new_app_service_plan ? (
    var.app_service_plan_name != "" ? var.app_service_plan_name : "${var.web_app_name}-plan"
  ) : ""
  app_insights_name_final = var.enable_application_insights ? (
    var.app_insights_name != "" ? var.app_insights_name : "${var.web_app_name}-insights"
  ) : ""

  # Base app settings
  base_app_settings = merge(
    var.enable_application_insights ? {
      APPINSIGHTS_INSTRUMENTATIONKEY           = azurerm_application_insights.main[0].instrumentation_key
      APPLICATIONINSIGHTS_CONNECTION_STRING    = azurerm_application_insights.main[0].connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {},
    var.app_settings
  )

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "web-app"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

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

# Linux Web App
resource "azurerm_linux_web_app" "main" {
  count                      = var.os_type == "Linux" ? 1 : 0
  name                       = var.web_app_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = var.create_new_app_service_plan ? azurerm_service_plan.main[0].id : var.app_service_plan_id
  https_only                 = var.enable_https_only
  public_network_access_enabled = var.enable_public_network_access
  tags                       = local.common_tags

  site_config {
    always_on         = var.sku_name != "F1" && var.sku_name != "D1" ? var.always_on : false
    minimum_tls_version = var.minimum_tls_version

    dynamic "application_stack" {
      for_each = var.runtime_stack == "PYTHON" ? [1] : []
      content {
        python_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "NODE" ? [1] : []
      content {
        node_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "DOTNETCORE" ? [1] : []
      content {
        dotnet_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "JAVA" ? [1] : []
      content {
        java_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "PHP" ? [1] : []
      content {
        php_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "RUBY" ? [1] : []
      content {
        ruby_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "GO" ? [1] : []
      content {
        go_version = var.runtime_version
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

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "virtual_network_subnet_id" {
    for_each = var.enable_vnet_integration && var.subnet_id != null ? [1] : []
    content {
      virtual_network_subnet_id = var.subnet_id
    }
  }
}

# Windows Web App
resource "azurerm_windows_web_app" "main" {
  count                      = var.os_type == "Windows" ? 1 : 0
  name                       = var.web_app_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = var.create_new_app_service_plan ? azurerm_service_plan.main[0].id : var.app_service_plan_id
  https_only                 = var.enable_https_only
  public_network_access_enabled = var.enable_public_network_access
  tags                       = local.common_tags

  site_config {
    always_on         = var.sku_name != "F1" && var.sku_name != "D1" ? var.always_on : false
    minimum_tls_version = var.minimum_tls_version

    dynamic "application_stack" {
      for_each = var.runtime_stack == "PYTHON" ? [1] : []
      content {
        python_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "NODE" ? [1] : []
      content {
        node_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "DOTNETCORE" ? [1] : []
      content {
        dotnet_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "JAVA" ? [1] : []
      content {
        java_version = var.runtime_version
      }
    }

    dynamic "application_stack" {
      for_each = var.runtime_stack == "PHP" ? [1] : []
      content {
        php_version = var.runtime_version
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

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "virtual_network_subnet_id" {
    for_each = var.enable_vnet_integration && var.subnet_id != null ? [1] : []
    content {
      virtual_network_subnet_id = var.subnet_id
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "web_app_id" {
  description = "ID of the web app"
  value       = var.os_type == "Linux" ? azurerm_linux_web_app.main[0].id : azurerm_windows_web_app.main[0].id
}

output "web_app_name" {
  description = "Name of the web app"
  value       = var.web_app_name
}

output "web_app_default_hostname" {
  description = "Default hostname of the web app"
  value       = var.os_type == "Linux" ? azurerm_linux_web_app.main[0].default_hostname : azurerm_windows_web_app.main[0].default_hostname
}

output "web_app_url" {
  description = "URL of the web app"
  value       = var.enable_https_only ? (
    var.os_type == "Linux" ? "https://${azurerm_linux_web_app.main[0].default_hostname}" : "https://${azurerm_windows_web_app.main[0].default_hostname}"
  ) : (
    var.os_type == "Linux" ? "http://${azurerm_linux_web_app.main[0].default_hostname}" : "http://${azurerm_windows_web_app.main[0].default_hostname}"
  )
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
