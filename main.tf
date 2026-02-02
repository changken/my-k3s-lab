terraform {
  cloud {
    organization = "changkenkai"
    workspaces {
      name = "my-k3s-lab"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Locals (variables defined in variables.tf)
locals {
  emergency_ssh_public_key = trimspace(file(pathexpand(var.emergency_ssh_public_key_path)))
}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "my-k3s-lab-rg"
  location = "japaneast"
}

# 2. Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "my-k3s-lab-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 3. Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "my-k3s-lab-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]

  default_outbound_access_enabled = true
}

# 4. NIC
resource "azurerm_network_interface" "nic" {
  name                = "my-k3s-lab-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "my-k3s-lab-ip-config"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 5. VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "my-k3s-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = local.emergency_ssh_public_key
  }

  disable_password_authentication = true

  # Cloud-init script for automatic setup
  custom_data = base64encode(templatefile("${path.module}/user-data-azure.sh", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = "my-k3s-vm"
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
    name                 = "my-k3s-vm-osdisk"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # 修正: 為了匹配 Trusted Launch VM
  secure_boot_enabled = true
  vtpm_enabled        = true
}

# ============================================================================
# AWS Provider (for multi-cloud setup)
# ============================================================================

provider "aws" {
  region = var.aws_region
  # Credentials automatically loaded from:
  # - AWS CLI (aws configure)
  # - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
}
