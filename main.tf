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
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "emergency_ssh_public_key_path" {
  description = "Path to emergency SSH public key for VM access"
  type        = string
}

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
  name                = "my-k3s-vmVNET"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 3. Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "my-k3s-vmSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]

  default_outbound_access_enabled = true
}

# 4. NIC
resource "azurerm_network_interface" "nic" {
  name                = "my-k3s-vmVMNic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    # 修正名稱以匹配現有資源
    name                          = "ipconfigmy-k3s-vm"
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

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    name                 = "my-k3s-vm_OsDisk_1_afc75defde9b43baab67fd8965882565"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    # 修正: 使用 Gen2 Image
    sku     = "22_04-lts-gen2"
    version = "latest"
  }

  # 修正: 為了匹配 Trusted Launch VM
  secure_boot_enabled = true
  vtpm_enabled        = true
}
