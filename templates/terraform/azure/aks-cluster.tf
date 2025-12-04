# =========================================
# Azure Kubernetes Service (AKS) Cluster - Terraform Template
# =========================================
# This template creates an AKS cluster with:
# - System and user node pools
# - Network configuration (Azure CNI or kubenet)
# - Auto-scaling support
# - Azure AD integration
# - Monitoring with Container Insights
# - Azure Policy add-on
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

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,63}$", var.cluster_name))
    error_message = "Cluster name must be 1-63 characters, letters, numbers, and hyphens"
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

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,54}$", var.dns_prefix))
    error_message = "DNS prefix must be 1-54 characters, letters, numbers, and hyphens"
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version - affects features and compatibility (e.g., 1.28, 1.29)"
  type        = string
  default     = "1.29"
}

variable "sku_tier" {
  description = "SKU tier for the cluster - affects cost and SLA (Free = no SLA, Standard = 99.5% SLA, Premium = 99.95% SLA with zone redundancy)"
  type        = string

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "SKU tier must be Free, Standard, or Premium"
  }
}

# Default Node Pool Configuration
variable "default_node_pool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"

  validation {
    condition     = can(regex("^[a-z0-9]{1,12}$", var.default_node_pool_name))
    error_message = "Node pool name must be 1-12 lowercase alphanumeric characters"
  }
}

variable "default_node_pool_vm_size" {
  description = "VM size for default node pool - affects cost and performance (e.g., Standard_D2s_v3, Standard_D4s_v3)"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "default_node_pool_node_count" {
  description = "Initial number of nodes in default pool"
  type        = number
  default     = 3

  validation {
    condition     = var.default_node_pool_node_count >= 1 && var.default_node_pool_node_count <= 100
    error_message = "Node count must be between 1 and 100"
  }
}

variable "default_node_pool_min_count" {
  description = "Minimum number of nodes for auto-scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.default_node_pool_min_count >= 1 && var.default_node_pool_min_count <= 100
    error_message = "Min count must be between 1 and 100"
  }
}

variable "default_node_pool_max_count" {
  description = "Maximum number of nodes for auto-scaling"
  type        = number
  default     = 5

  validation {
    condition     = var.default_node_pool_max_count >= 1 && var.default_node_pool_max_count <= 100
    error_message = "Max count must be between 1 and 100"
  }
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the default node pool"
  type        = bool
  default     = true
}

variable "node_os_disk_size_gb" {
  description = "OS disk size in GB for nodes"
  type        = number
  default     = 30

  validation {
    condition     = var.node_os_disk_size_gb >= 30 && var.node_os_disk_size_gb <= 2048
    error_message = "OS disk size must be between 30 and 2048 GB"
  }
}

# Networking Configuration
variable "network_plugin" {
  description = "Network plugin - affects networking capabilities (azure = Azure CNI with pod IPs from VNet, kubenet = basic networking with NAT)"
  type        = string

  validation {
    condition     = contains(["azure", "kubenet"], var.network_plugin)
    error_message = "Network plugin must be azure or kubenet"
  }
}

variable "network_policy" {
  description = "Network policy - affects pod network security (azure = Azure Network Policies, calico = Calico Network Policies, empty = no network policy)"
  type        = string

  validation {
    condition     = contains(["azure", "calico", ""], var.network_policy)
    error_message = "Network policy must be azure, calico, or empty"
  }
}

variable "load_balancer_sku" {
  description = "SKU for load balancer - affects features (basic = limited features, standard = recommended with availability zones and more features)"
  type        = string

  validation {
    condition     = contains(["basic", "standard"], var.load_balancer_sku)
    error_message = "Load balancer SKU must be basic or standard"
  }
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for DNS service (must be within service_cidr)"
  type        = string
  default     = "10.0.0.10"
}

variable "docker_bridge_cidr" {
  description = "CIDR for Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
}

# Security & Monitoring
variable "enable_azure_ad_rbac" {
  description = "Enable Azure AD RBAC for Kubernetes authorization"
  type        = bool
  default     = false
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy add-on"
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable Container Insights monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Container Insights (required if enable_container_insights is true)"
  type        = string
  default     = null
}

variable "enable_http_application_routing" {
  description = "Enable HTTP application routing add-on"
  type        = bool
  default     = false
}

# Identity
variable "identity_type" {
  description = "Type of identity for AKS cluster (SystemAssigned = managed by Azure, UserAssigned = you manage the identity)"
  type        = string

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "Identity type must be SystemAssigned or UserAssigned"
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
  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "aks-cluster"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Log Analytics Workspace (if Container Insights enabled and no workspace provided)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_container_insights && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "${var.cluster_name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = local.common_tags

  default_node_pool {
    name                = var.default_node_pool_name
    vm_size             = var.default_node_pool_vm_size
    node_count          = var.enable_auto_scaling ? null : var.default_node_pool_node_count
    min_count           = var.enable_auto_scaling ? var.default_node_pool_min_count : null
    max_count           = var.enable_auto_scaling ? var.default_node_pool_max_count : null
    enable_auto_scaling = var.enable_auto_scaling
    os_disk_size_gb     = var.node_os_disk_size_gb
    type                = "VirtualMachineScaleSets"
  }

  identity {
    type = var.identity_type
  }

  network_profile {
    network_plugin    = var.network_plugin
    network_policy    = var.network_policy != "" ? var.network_policy : null
    load_balancer_sku = var.load_balancer_sku
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    docker_bridge_cidr = var.docker_bridge_cidr
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_ad_rbac ? [1] : []
    content {
      managed                = true
      azure_rbac_enabled     = true
    }
  }

  dynamic "oms_agent" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.main[0].id
    }
  }

  dynamic "azure_policy" {
    for_each = var.enable_azure_policy ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "http_application_routing" {
    for_each = var.enable_http_application_routing ? [1] : []
    content {
      enabled = true
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kube_config" {
  description = "Kubernetes configuration"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubelet_identity" {
  description = "Kubelet identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity
}

output "node_resource_group" {
  description = "Resource group for AKS-managed resources"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = var.enable_container_insights ? (var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.main[0].id) : null
}
