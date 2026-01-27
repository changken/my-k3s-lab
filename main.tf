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
variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
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
}

# 4. Public IP
resource "azurerm_public_ip" "pip" {
  name                = "my-k3s-vmPublicIP"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 5. NSG
resource "azurerm_network_security_group" "nsg" {
  name                = "my-k3s-vmNSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "118.150.143.171/32"
    destination_address_prefix = "*"
  }
}

# 6. NIC
resource "azurerm_network_interface" "nic" {
  name                = "my-k3s-vmVMNic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    # 修正名稱以匹配現有資源
    name                          = "ipconfigmy-k3s-vm"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 7. VM
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
    public_key = var.ssh_public_key
  }

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
