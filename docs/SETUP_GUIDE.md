# Azure K3s 開發環境建置指南

本文件記錄如何在 Azure 上建立輕量級 Kubernetes (K3s) 開發環境，並透過 Tailscale 建立安全連線，最後使用 Terraform 進行基礎設施即程式碼 (IaC) 管理。

---

## 1. 環境需求

| 工具 | 用途 | 安裝連結 |
|------|------|----------|
| Azure CLI | Azure 資源管理 | [安裝指南](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| Terraform | 基礎設施管理 | [下載頁面](https://www.terraform.io/downloads) |
| Tailscale | VPN 連線 | [安裝指南](https://tailscale.com/download) |
| kubectl | Kubernetes 操作 | [安裝指南](https://kubernetes.io/docs/tasks/tools/) |

---

## 2. 手動建立環境（CLI 方式）

> 此章節僅供參考，說明專案最初如何以 Azure CLI 建立。目前已改用 Terraform 管理。

### 2.1 建立 Azure 資源

```bash
# 產生 repo-local SSH Key（備援用，避免汙染 ~/.ssh）
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# 建立 Resource Group
az group create --name my-k3s-lab-rg --location japaneast

# 建立 VM (Standard_B2s / Ubuntu 22.04)
az vm create \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username ubuntu \
  --ssh-key-values ./.ssh/azure_emergency_ed25519.pub \
  --public-ip-sku Standard
```

### 2.2 安裝 Tailscale 與 K3s

```bash
# 安裝 Tailscale 並啟動服務（Run Command）
az vm run-command invoke \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "curl -fsSL https://tailscale.com/install.sh | sh" "sudo systemctl enable --now tailscaled"

# 取得登入 URL（輸出中會顯示）
az vm run-command invoke \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo tailscale login"

# 完成授權後，開啟 Tailscale SSH
az vm run-command invoke \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo tailscale up --ssh"
```

接著使用 Tailscale SSH 進入 VM：

```bash
tailscale ssh ubuntu@my-k3s-vm

# 取得 Tailscale IP
TS_IP=$(tailscale ip -4)
echo "Tailscale IP: $TS_IP"

# 安裝 K3s（加入 Tailscale IP 到 TLS SAN）
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP
```

---

## 3. Terraform 管理

### 3.1 設定變數

```bash
# 產生 repo-local SSH Key（備援用，避免汙染 ~/.ssh）
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# 複製範例檔案
cp terraform.tfvars.example terraform.tfvars

# 編輯並填入變數
vim terraform.tfvars
```

**terraform.tfvars 內容：**
```hcl
emergency_ssh_public_key_path = "./.ssh/azure_emergency_ed25519.pub"
backup_ssh_enabled             = false
backup_ssh_source_cidr         = "1.1.1.1/32" # 改成你的家用 CIDR
```

### 3.2 Terraform Cloud 設定

1. 前往 [Terraform Cloud](https://app.terraform.io) 註冊/登入
2. 建立 Organization 和 Workspace
3. 在 Workspace Settings → General → **Execution Mode** 選擇 `Local`
4. 執行以下指令：

```bash
# 登入 Terraform Cloud
terraform login

# 初始化（首次會詢問是否遷移 state）
terraform init

# 檢查配置
terraform plan
```

### 3.3 資源匯入（僅供參考）

若要將現有 Azure 資源導入 Terraform 管理：

```bash
# 使用環境變數或自動取得 Subscription ID
SUB_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
RG_ID="/subscriptions/$SUB_ID/resourceGroups/my-k3s-lab-rg"

# 初始化
terraform init

# 匯入各項資源
terraform import azurerm_resource_group.rg "$RG_ID"
terraform import azurerm_virtual_network.vnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-vmVNET"
terraform import azurerm_subnet.subnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-vmVNET/subnets/my-k3s-vmSubnet"
terraform import azurerm_public_ip.pip "$RG_ID/providers/Microsoft.Network/publicIPAddresses/my-k3s-vmPublicIP"
terraform import azurerm_network_security_group.nsg "$RG_ID/providers/Microsoft.Network/networkSecurityGroups/my-k3s-vmNSG"
terraform import azurerm_network_interface.nic "$RG_ID/providers/Microsoft.Network/networkInterfaces/my-k3s-vmVMNic"
terraform import azurerm_linux_virtual_machine.vm "$RG_ID/providers/Microsoft.Compute/virtualMachines/my-k3s-vm"
```

---

## 4. 日常操作

### 4.1 取得 Kubeconfig

```bash
# Tailscale SSH 進入 VM
tailscale ssh ubuntu@<YOUR_TAILSCALE_IP>

# 複製 kubeconfig 到本地
sudo cat /etc/rancher/k3s/k3s.yaml
```

將內容存到本地 `kubeconfig/k3s-azure.yaml`，並修改 `server` 為你的 Tailscale IP：

```yaml
# 修改前
server: https://127.0.0.1:6443

# 修改後
server: https://<YOUR_TAILSCALE_IP>:6443
```

### 4.2 使用 kubectl

```bash
# 設定環境變數
export KUBECONFIG=$(pwd)/kubeconfig/k3s-azure.yaml

# 測試連線
kubectl get nodes
kubectl get pods -A
```

### 4.3 關機省錢

```bash
# 關機（停止計費 CPU/Memory，保留磁碟和 IP）
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm

# 開機
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm

# 開機後約 1-2 分鐘，Tailscale 和 K3s 會自動啟動
```

### 4.4 備援 SSH（必要時）

```bash
# 在 terraform.tfvars 中暫時打開備援 SSH
# backup_ssh_enabled = true
# backup_ssh_source_cidr = "<YOUR_HOME_CIDR>"

terraform apply

# 使用 repo-local key（不寫入 ~/.ssh）
ssh -F /dev/null -i ./.ssh/azure_emergency_ed25519 -o UserKnownHostsFile=./.ssh/known_hosts -o StrictHostKeyChecking=accept-new ubuntu@<YOUR_VM_PUBLIC_IP>

# 修復後關回
# backup_ssh_enabled = false
terraform apply
```

---

## 5. 清理資源

### 使用 Terraform（推薦）

```bash
# 刪除所有資源
terraform destroy
```

### 使用 Azure CLI

```bash
# 刪除整個 Resource Group
az group delete --name my-k3s-lab-rg --yes
```

---

## 6. 疑難排解

### kubectl 連不上

```bash
# 確認 Tailscale 連線
tailscale status

# 確認 VM 是否啟動
az vm list -d --query "[?name=='my-k3s-vm'].powerState" -o tsv

# Tailscale SSH 進 VM 檢查 K3s 狀態
tailscale ssh ubuntu@<YOUR_TAILSCALE_IP>
sudo systemctl status k3s
```

### Terraform Plan 顯示差異

常見原因：
- **OS Disk 名稱不符**：Azure 自動生成的名稱包含 GUID，需在 `main.tf` 中指定
- **Gen2 / Trusted Launch 設定**：確保 `secure_boot_enabled = true` 和 `vtpm_enabled = true`
- **Image SKU**：使用 `22_04-lts-gen2` 而非 `22_04-lts`

---

## 7. 參考資料

- [K3s 官方文件](https://docs.k3s.io/)
- [Tailscale 官方文件](https://tailscale.com/kb/)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform Cloud](https://app.terraform.io/)
