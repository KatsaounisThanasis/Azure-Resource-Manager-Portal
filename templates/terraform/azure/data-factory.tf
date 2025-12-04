# =========================================
# Azure Data Factory - Terraform Template
# =========================================
# This template creates a Data Factory with:
# - Managed identity
# - Git integration (Azure DevOps or GitHub)
# - Public network access configuration
# - Customer-managed key encryption
# - Linked services placeholders
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

variable "data_factory_name" {
  description = "Name of the Data Factory (globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,63}$", var.data_factory_name))
    error_message = "Data Factory name must be 3-63 characters, letters, numbers, and hyphens"
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

variable "identity_type" {
  description = "Type of identity (SystemAssigned, UserAssigned, or SystemAssigned,UserAssigned)"
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned,UserAssigned"], var.identity_type)
    error_message = "Identity type must be SystemAssigned, UserAssigned, or SystemAssigned,UserAssigned"
  }
}

variable "user_assigned_identity_ids" {
  description = "List of user-assigned identity IDs"
  type        = list(string)
  default     = []
}

variable "public_network_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "managed_virtual_network_enabled" {
  description = "Enable managed virtual network"
  type        = bool
  default     = false
}

variable "enable_git_configuration" {
  description = "Enable Git repository configuration"
  type        = bool
  default     = false
}

variable "git_account_name" {
  description = "Git account name (Azure DevOps organization or GitHub user)"
  type        = string
  default     = ""
}

variable "git_project_name" {
  description = "Git project name (Azure DevOps project)"
  type        = string
  default     = ""
}

variable "git_repository_name" {
  description = "Git repository name"
  type        = string
  default     = ""
}

variable "git_branch_name" {
  description = "Git branch name"
  type        = string
  default     = "main"
}

variable "git_root_folder" {
  description = "Root folder path in Git repository"
  type        = string
  default     = "/"
}

variable "git_url" {
  description = "Git repository URL (for GitHub)"
  type        = string
  default     = ""
}

variable "enable_customer_managed_key" {
  description = "Enable customer-managed key encryption"
  type        = bool
  default     = false
}

variable "key_vault_key_id" {
  description = "Key Vault key ID for encryption"
  type        = string
  default     = null
}

variable "global_parameters" {
  description = "Global parameters for the Data Factory"
  type = map(object({
    type  = string
    value = string
  }))
  default = {}
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
      Template  = "data-factory"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

resource "azurerm_data_factory" "main" {
  name                            = var.data_factory_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  public_network_enabled          = var.public_network_enabled
  managed_virtual_network_enabled = var.managed_virtual_network_enabled
  tags                            = local.common_tags

  identity {
    type         = var.identity_type
    identity_ids = contains(["UserAssigned", "SystemAssigned,UserAssigned"], var.identity_type) ? var.user_assigned_identity_ids : null
  }

  dynamic "github_configuration" {
    for_each = var.enable_git_configuration && var.git_url != "" ? [1] : []
    content {
      account_name    = var.git_account_name
      repository_name = var.git_repository_name
      branch_name     = var.git_branch_name
      root_folder     = var.git_root_folder
      git_url         = var.git_url
    }
  }

  dynamic "vsts_configuration" {
    for_each = var.enable_git_configuration && var.git_project_name != "" ? [1] : []
    content {
      account_name    = var.git_account_name
      project_name    = var.git_project_name
      repository_name = var.git_repository_name
      branch_name     = var.git_branch_name
      root_folder     = var.git_root_folder
      tenant_id       = data.azurerm_client_config.current.tenant_id
    }
  }

  dynamic "customer_managed_key_id" {
    for_each = var.enable_customer_managed_key && var.key_vault_key_id != null ? [1] : []
    content {
      key_vault_key_id = var.key_vault_key_id
    }
  }

  dynamic "global_parameter" {
    for_each = var.global_parameters
    content {
      name  = global_parameter.key
      type  = global_parameter.value.type
      value = global_parameter.value.value
    }
  }
}

data "azurerm_client_config" "current" {}

# =========================================
# OUTPUTS
# =========================================

output "data_factory_id" {
  description = "ID of the Data Factory"
  value       = azurerm_data_factory.main.id
}

output "data_factory_name" {
  description = "Name of the Data Factory"
  value       = azurerm_data_factory.main.name
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity"
  value       = contains(["SystemAssigned", "SystemAssigned,UserAssigned"], var.identity_type) ? azurerm_data_factory.main.identity[0].principal_id : null
}

output "identity_tenant_id" {
  description = "Tenant ID of the identity"
  value       = azurerm_data_factory.main.identity[0].tenant_id
}
