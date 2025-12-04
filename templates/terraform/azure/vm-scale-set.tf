# =========================================
# Azure Virtual Machine Scale Set - Terraform Template
# =========================================
# This template creates a VM Scale Set with:
# - Linux or Windows VMs
# - Auto-scaling configuration
# - Load balancer integration
# - Custom script extension support
# - Health probe configuration
# - Upgrade policy (Automatic, Manual, Rolling)
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

variable "vmss_name" {
  description = "Name of the virtual machine scale set"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.vmss_name))
    error_message = "VMSS name must be 1-64 characters, letters, numbers, and hyphens"
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

variable "vm_sku" {
  description = "VM SKU for scale set instances"
  type        = string
  default     = "Standard_D2s_v3"

  validation {
    condition     = can(regex("^Standard_[A-Z][0-9]+[a-z]*_v[0-9]+$|^Standard_[A-Z][0-9]+[a-z]*$", var.vm_sku))
    error_message = "VM SKU must be a valid Azure VM size"
  }
}

variable "instances" {
  description = "Initial number of instances in the scale set"
  type        = number
  default     = 2

  validation {
    condition     = var.instances >= 0 && var.instances <= 1000
    error_message = "Instances must be between 0 and 1000"
  }
}

variable "admin_username" {
  description = "Admin username for VM instances"
  type        = string
  default     = "azureuser"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,31}$", var.admin_username))
    error_message = "Admin username must start with a letter and be 1-32 characters"
  }
}

variable "admin_password" {
  description = "Admin password for Windows or SSH public key for Linux"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "Admin password must be at least 12 characters long"
  }
}

variable "os_type" {
  description = "Operating system type (Linux or Windows)"
  type        = string
  default     = "Linux"

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be Linux or Windows"
  }
}

# Image Configuration
variable "image_publisher" {
  description = "OS image publisher"
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "OS image offer"
  type        = string
  default     = "0001-com-ubuntu-server-jammy"
}

variable "image_sku" {
  description = "OS image SKU"
  type        = string
  default     = "22_04-lts-gen2"
}

variable "image_version" {
  description = "OS image version"
  type        = string
  default     = "latest"
}

# Disk Configuration
variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 128

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 4095
    error_message = "OS disk size must be between 30 and 4095 GB"
  }
}

variable "os_disk_type" {
  description = "OS disk type"
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_type)
    error_message = "OS disk type must be Standard_LRS, StandardSSD_LRS, or Premium_LRS"
  }
}

# Networking
variable "subnet_id" {
  description = "Subnet ID for VM scale set"
  type        = string
}

variable "enable_public_ip" {
  description = "Enable public IP for each instance"
  type        = bool
  default     = false
}

variable "enable_accelerated_networking" {
  description = "Enable accelerated networking"
  type        = bool
  default     = false
}

# Load Balancer
variable "enable_load_balancer" {
  description = "Create and attach load balancer"
  type        = bool
  default     = true
}

variable "load_balancer_backend_pool_ids" {
  description = "Existing load balancer backend pool IDs (if not creating new LB)"
  type        = list(string)
  default     = []
}

# Upgrade Policy
variable "upgrade_mode" {
  description = "Upgrade mode (Automatic, Manual, Rolling)"
  type        = string
  default     = "Manual"

  validation {
    condition     = contains(["Automatic", "Manual", "Rolling"], var.upgrade_mode)
    error_message = "Upgrade mode must be Automatic, Manual, or Rolling"
  }
}

# Auto-scaling
variable "enable_autoscale" {
  description = "Enable auto-scaling"
  type        = bool
  default     = true
}

variable "autoscale_min_capacity" {
  description = "Minimum number of instances for auto-scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.autoscale_min_capacity >= 0 && var.autoscale_min_capacity <= 1000
    error_message = "Min capacity must be between 0 and 1000"
  }
}

variable "autoscale_max_capacity" {
  description = "Maximum number of instances for auto-scaling"
  type        = number
  default     = 10

  validation {
    condition     = var.autoscale_max_capacity >= 0 && var.autoscale_max_capacity <= 1000
    error_message = "Max capacity must be between 0 and 1000"
  }
}

variable "autoscale_default_capacity" {
  description = "Default number of instances for auto-scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.autoscale_default_capacity >= 0 && var.autoscale_default_capacity <= 1000
    error_message = "Default capacity must be between 0 and 1000"
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
      Template  = "vm-scale-set"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  count               = var.enable_load_balancer ? 1 : 0
  name                = "${var.vmss_name}-lb-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Load Balancer
resource "azurerm_lb" "main" {
  count               = var.enable_load_balancer ? 1 : 0
  name                = "${var.vmss_name}-lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }
}

# Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
  count           = var.enable_load_balancer ? 1 : 0
  loadbalancer_id = azurerm_lb.main[0].id
  name            = "${var.vmss_name}-backend-pool"
}

# Load Balancer Health Probe
resource "azurerm_lb_probe" "main" {
  count               = var.enable_load_balancer ? 1 : 0
  loadbalancer_id     = azurerm_lb.main[0].id
  name                = "http-probe"
  protocol            = "Http"
  port                = 80
  request_path        = "/"
}

# Load Balancer Rule
resource "azurerm_lb_rule" "main" {
  count                          = var.enable_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.main[0].id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main[0].id]
  probe_id                       = azurerm_lb_probe.main[0].id
}

# Linux VM Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  count               = var.os_type == "Linux" ? 1 : 0
  name                = var.vmss_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_sku
  instances           = var.instances
  admin_username      = var.admin_username
  upgrade_mode        = var.upgrade_mode
  tags                = local.common_tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_password
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  os_disk {
    storage_account_type = var.os_disk_type
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
  }

  network_interface {
    name    = "${var.vmss_name}-nic"
    primary = true
    enable_accelerated_networking = var.enable_accelerated_networking

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.subnet_id

      dynamic "public_ip_address" {
        for_each = var.enable_public_ip ? [1] : []
        content {
          name = "${var.vmss_name}-pip"
        }
      }

      load_balancer_backend_address_pool_ids = var.enable_load_balancer ? [azurerm_lb_backend_address_pool.main[0].id] : var.load_balancer_backend_pool_ids
    }
  }

  disable_password_authentication = true
}

# Windows VM Scale Set
resource "azurerm_windows_virtual_machine_scale_set" "main" {
  count               = var.os_type == "Windows" ? 1 : 0
  name                = var.vmss_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_sku
  instances           = var.instances
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  upgrade_mode        = var.upgrade_mode
  tags                = local.common_tags

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  os_disk {
    storage_account_type = var.os_disk_type
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
  }

  network_interface {
    name    = "${var.vmss_name}-nic"
    primary = true
    enable_accelerated_networking = var.enable_accelerated_networking

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.subnet_id

      dynamic "public_ip_address" {
        for_each = var.enable_public_ip ? [1] : []
        content {
          name = "${var.vmss_name}-pip"
        }
      }

      load_balancer_backend_address_pool_ids = var.enable_load_balancer ? [azurerm_lb_backend_address_pool.main[0].id] : var.load_balancer_backend_pool_ids
    }
  }
}

# Auto-scale Settings
resource "azurerm_monitor_autoscale_setting" "main" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "${var.vmss_name}-autoscale"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = var.os_type == "Linux" ? azurerm_linux_virtual_machine_scale_set.main[0].id : azurerm_windows_virtual_machine_scale_set.main[0].id
  tags                = local.common_tags

  profile {
    name = "defaultProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = var.os_type == "Linux" ? azurerm_linux_virtual_machine_scale_set.main[0].id : azurerm_windows_virtual_machine_scale_set.main[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = var.os_type == "Linux" ? azurerm_linux_virtual_machine_scale_set.main[0].id : azurerm_windows_virtual_machine_scale_set.main[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "vmss_id" {
  description = "ID of the VM scale set"
  value       = var.os_type == "Linux" ? azurerm_linux_virtual_machine_scale_set.main[0].id : azurerm_windows_virtual_machine_scale_set.main[0].id
}

output "vmss_name" {
  description = "Name of the VM scale set"
  value       = var.vmss_name
}

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = var.enable_load_balancer ? azurerm_lb.main[0].id : null
}

output "load_balancer_public_ip" {
  description = "Public IP of the load balancer"
  value       = var.enable_load_balancer ? azurerm_public_ip.lb[0].ip_address : null
}
