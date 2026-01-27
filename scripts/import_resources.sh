#!/bin/bash
set -e

# 切換到目錄
cd terraform-k3s

# 清理舊的 state (如果有)
rm -f terraform.tfstate terraform.tfstate.backup

# 初始化
echo "Initializing Terraform..."
terraform init

# 定義資源 ID 前綴 (方便閱讀)
# 優先使用環境變數，若無則自動從 az cli 取得
SUB_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
RG_ID="/subscriptions/$SUB_ID/resourceGroups/my-k3s-lab-rg"

echo "Importing Resource Group..."
terraform import azurerm_resource_group.rg "$RG_ID"

echo "Importing VNet..."
terraform import azurerm_virtual_network.vnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-vmVNET"

echo "Importing Subnet..."
terraform import azurerm_subnet.subnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-vmVNET/subnets/my-k3s-vmSubnet"

echo "Importing Public IP..."
terraform import azurerm_public_ip.pip "$RG_ID/providers/Microsoft.Network/publicIPAddresses/my-k3s-vmPublicIP"

echo "Importing NSG..."
terraform import azurerm_network_security_group.nsg "$RG_ID/providers/Microsoft.Network/networkSecurityGroups/my-k3s-vmNSG"

echo "Importing NIC..."
terraform import azurerm_network_interface.nic "$RG_ID/providers/Microsoft.Network/networkInterfaces/my-k3s-vmVMNic"

echo "Importing VM..."
terraform import azurerm_linux_virtual_machine.vm "$RG_ID/providers/Microsoft.Compute/virtualMachines/my-k3s-vm"

echo "Import Complete! Running Plan..."
terraform plan
