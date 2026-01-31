# Azure K3s 開發環境建置指南

本文件記錄專案的詳細建置過程，包含手動 CLI 方式與 Terraform 資源匯入，作為歷史參考。

> [!NOTE]
> 日常操作請參閱 [README.md](../README.md)

---

## 1. 手動建立環境（CLI 方式）

> 此章節為歷史記錄，說明專案最初如何以 Azure CLI 建立。

### 建立 Azure 資源

```bash
# 產生 repo-local SSH Key
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# 建立 Resource Group
az group create --name my-k3s-lab-rg --location japaneast

# 建立 VM
az vm create \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username ubuntu \
  --ssh-key-values ./.ssh/azure_emergency_ed25519.pub \
  --public-ip-sku Standard
```

### 安裝 Tailscale 與 K3s

```bash
# 透過 Tailscale SSH 進入 VM 後執行
TS_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP
```

---

## 2. Terraform 資源匯入

若要將現有 Azure 資源導入 Terraform 管理：

```bash
# 取得 Subscription ID
SUB_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
RG_ID="/subscriptions/$SUB_ID/resourceGroups/my-k3s-lab-rg"

# 初始化
terraform init

# 匯入各項資源
terraform import azurerm_resource_group.rg "$RG_ID"
terraform import azurerm_virtual_network.vnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-lab-vnet"
terraform import azurerm_subnet.subnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-lab-vnet/subnets/my-k3s-lab-subnet"
terraform import azurerm_network_interface.nic "$RG_ID/providers/Microsoft.Network/networkInterfaces/my-k3s-lab-nic"
terraform import azurerm_linux_virtual_machine.vm "$RG_ID/providers/Microsoft.Compute/virtualMachines/my-k3s-vm"
```

---

## 3. Terraform Cloud 設定

1. 前往 [Terraform Cloud](https://app.terraform.io) 註冊/登入
2. 建立 Organization 和 Workspace
3. **重要**：Workspace Settings → General → Execution Mode 選擇 `Local`
4. 執行 `terraform login` 完成認證

---

## 4. 常見問題

### Terraform Plan 顯示差異

| 原因 | 解法 |
|------|------|
| OS Disk 名稱不符 | 在 `main.tf` 中指定完整 disk 名稱 |
| Trusted Launch | 確保 `secure_boot_enabled = true`, `vtpm_enabled = true` |
| Image 不符 | 確認使用 `ubuntu-24_04-lts` offer |

---

## 5. 參考資料

- [K3s 官方文件](https://docs.k3s.io/)
- [Tailscale 官方文件](https://tailscale.com/kb/)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
