# =========================================
# Azure Virtual Machine - Terraform Template
# =========================================
# This template creates a complete VM setup including:
# - Virtual Network with subnet
# - Network Security Group with configurable rules
# - Public IP address
# - Network Interface
# - Linux or Windows Virtual Machine
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

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.vm_name))
    error_message = "VM name must be 1-64 characters and contain only letters, numbers, and hyphens"
  }
}

variable "location" {
  description = "Azure region for deployment (e.g., norwayeast, swedencentral)"
  type        = string
  default = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[-\\w\\._\\(\\)]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, underscores, hyphens, periods, and parentheses"
  }
}

variable "vm_size" {
  description = "Size of the virtual machine - affects cost and performance (Standard_B1s=burstable/low cost, Standard_D2s_v3=general purpose, Standard_E2s_v3=memory optimized)"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,31}$", var.admin_username))
    error_message = "Admin username must start with a letter and be 1-32 characters"
  }
}

variable "admin_password" {
  description = "Admin password for Windows VM or SSH public key for Linux VM"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "Admin password must be at least 12 characters long"
  }
}

variable "os_type" {
  description = "Operating system type - affects licensing and features (Linux or Windows)"

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be either Linux or Windows"
  }
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 128

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 4095
    error_message = "OS disk size must be between 30 and 4095 GB"
  }
}

variable "os_disk_type" {
  description = "Type of the OS disk - affects cost and performance (Standard_LRS=HDD, StandardSSD_LRS=balanced SSD, Premium_LRS=high performance SSD)"
  type        = string

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "UltraSSD_LRS"], var.os_disk_type)
    error_message = "OS disk type must be Standard_LRS, StandardSSD_LRS, Premium_LRS, or UltraSSD_LRS"
  }
}

# Linux Image Configuration
variable "linux_image_publisher" {
  description = "Publisher of the Linux OS image"
  type        = string
  default     = "Canonical"
}

variable "linux_image_offer" {
  description = "Offer of the Linux OS image"
  type        = string
  default     = "0001-com-ubuntu-server-jammy"
}

variable "linux_image_sku" {
  description = "SKU of the Linux OS image"
  type        = string
  default     = "22_04-lts-gen2"
}

variable "linux_image_version" {
  description = "Version of the Linux OS image"
  type        = string
  default     = "latest"
}

# Windows Image Configuration
variable "windows_image_publisher" {
  description = "Publisher of the Windows OS image"
  type        = string
  default     = "MicrosoftWindowsServer"
}

variable "windows_image_offer" {
  description = "Offer of the Windows OS image"
  type        = string
  default     = "WindowsServer"
}

variable "windows_image_sku" {
  description = "SKU of the Windows OS image"
  type        = string
  default     = "2022-Datacenter"
}

variable "windows_image_version" {
  description = "Version of the Windows OS image"
  type        = string
  default     = "latest"
}

# Networking Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network (CIDR notation)"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.vnet_address_space : can(cidrhost(cidr, 0))])
    error_message = "All address spaces must be valid CIDR blocks"
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet (CIDR notation)"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block"
  }
}

variable "public_ip_allocation_method" {
  description = "Allocation method for the public IP (Static or Dynamic)"
  type        = string
  default     = "Dynamic"
}

variable "public_ip_sku" {
  description = "SKU for the public IP (Basic or Standard)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard"], var.public_ip_sku)
    error_message = "Public IP SKU must be Basic or Standard"
  }
}

# Security Configuration
variable "enable_ssh_access" {
  description = "Enable SSH access (port 22) for Linux VMs"
  type        = bool
  default     = true
}

variable "enable_rdp_access" {
  description = "Enable RDP access (port 3389) for Windows VMs"
  type        = bool
  default     = true
}

variable "enable_http_access" {
  description = "Enable HTTP access (port 80)"
  type        = bool
  default     = false
}

variable "enable_https_access" {
  description = "Enable HTTPS access (port 443)"
  type        = bool
  default     = false
}

variable "allowed_source_address_prefix" {
  description = "Source address prefix allowed for inbound connections (* = all)"
  type        = string
  default     = "*"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_boot_diagnostics" {
  description = "Enable boot diagnostics for the VM"
  type        = bool
  default     = true
}

# =========================================
# LOCAL VARIABLES
# =========================================

locals {
  # Resource naming
  vnet_name   = "${var.vm_name}-vnet"
  subnet_name = "${var.vm_name}-subnet"
  nsg_name    = "${var.vm_name}-nsg"
  pip_name    = "${var.vm_name}-pip"
  nic_name    = "${var.vm_name}-nic"

  # Security rules based on OS type
  default_security_rules = concat(
    var.os_type == "Linux" && var.enable_ssh_access ? [
      {
        name                       = "AllowSSH"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = var.allowed_source_address_prefix
        destination_address_prefix = "*"
        description                = "Allow SSH access"
      }
    ] : [],
    var.os_type == "Windows" && var.enable_rdp_access ? [
      {
        name                       = "AllowRDP"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = var.allowed_source_address_prefix
        destination_address_prefix = "*"
        description                = "Allow RDP access"
      }
    ] : [],
    var.enable_http_access ? [
      {
        name                       = "AllowHTTP"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = var.allowed_source_address_prefix
        destination_address_prefix = "*"
        description                = "Allow HTTP access"
      }
    ] : [],
    var.enable_https_access ? [
      {
        name                       = "AllowHTTPS"
        priority                   = 120
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = var.allowed_source_address_prefix
        destination_address_prefix = "*"
        description                = "Allow HTTPS access"
      }
    ] : []
  )

  # Common tags
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Template  = "virtual-machine"
    }
  )
}

# =========================================
# RESOURCES
# =========================================

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = local.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  dynamic "security_rule" {
    for_each = local.default_security_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
      description                = security_rule.value.description
    }
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = local.pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  tags                = local.common_tags
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = local.nic_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  count               = var.os_type == "Linux" ? 1 : 0
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_password  # For Linux, this should be SSH public key
  }

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.linux_image_publisher
    offer     = var.linux_image_offer
    sku       = var.linux_image_sku
    version   = var.linux_image_version
  }

  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {
      storage_account_uri = null  # Uses managed storage account
    }
  }

  # Disable password authentication for Linux
  disable_password_authentication = true
}

# Windows Virtual Machine
resource "azurerm_windows_virtual_machine" "main" {
  count               = var.os_type == "Windows" ? 1 : 0
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.windows_image_publisher
    offer     = var.windows_image_offer
    sku       = var.windows_image_sku
    version   = var.windows_image_version
  }

  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {
      storage_account_uri = null  # Uses managed storage account
    }
  }
}

# =========================================
# OUTPUTS
# =========================================

output "vm_id" {
  description = "ID of the virtual machine"
  value       = var.os_type == "Linux" ? azurerm_linux_virtual_machine.main[0].id : azurerm_windows_virtual_machine.main[0].id
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = var.vm_name
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = azurerm_subnet.main.id
}

output "nsg_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.main.id
}

output "nic_id" {
  description = "ID of the network interface"
  value       = azurerm_network_interface.main.id
}

output "connection_info" {
  description = "Connection information for the VM"
  value = var.os_type == "Linux" ? {
    protocol = "SSH"
    command  = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
    port     = 22
    } : {
    protocol = "RDP"
    command  = "mstsc /v:${azurerm_public_ip.main.ip_address}"
    port     = 3389
  }
}
