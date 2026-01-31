# My K3s Lab on Azure

這是一個使用 Terraform 管理的 K3s 開發環境，部署在 Azure VM 上，並透過 Tailscale VPN 進行安全的遠端管理。

## ⚠️ 免責聲明

> **本專案僅供個人學習與實驗用途，不建議直接用於生產環境。**  
> **使用者需自行承擔所有風險，包括但不限於 Azure 服務費用、資料安全與服務穩定性。**  
> **作者不對任何因使用本專案而產生的損失負責。**

## 專案結構

```
my-k3s-lab/
├── main.tf                      # Terraform 主配置
├── terraform.tfvars.example     # 變數範例檔（可公開）
├── docs/SETUP_GUIDE.md          # 詳細建置記錄
└── kubeconfig/k3s-azure.yaml    # K3s kubeconfig（已忽略）
```

## 快速開始

### 前置需求

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 已登入
- [Tailscale](https://tailscale.com/) 帳號
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### 1. 初始化專案

```bash
git clone <your-repo-url>
cd my-k3s-lab

# 產生 repo-local SSH 金鑰
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# 設定變數
cp terraform.tfvars.example terraform.tfvars
```

### 2. 部署

```bash
terraform login   # 登入 Terraform Cloud
terraform init
terraform plan
terraform apply
```

### 3. 配置 Tailscale（首次部署後）

```bash
# 安裝 Tailscale
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "curl -fsSL https://tailscale.com/install.sh | sh" \
            "sudo systemctl enable --now tailscaled"

# 取得登入 URL 並完成授權
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo tailscale login"

# 啟用 Tailscale SSH
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo tailscale up --ssh"
```

### 4. 取得 Kubeconfig

```bash
# 透過 Tailscale SSH 進入 VM
tailscale ssh ubuntu@my-k3s-vm

# 在 VM 內執行
TS_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP
sudo cat /etc/rancher/k3s/k3s.yaml
```

將輸出存到 `kubeconfig/k3s-azure.yaml`，並將 `server` 改為 `https://<TAILSCALE_IP>:6443`。

## 日常操作

### 關機/開機（省費用）

```bash
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm  # 關機
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm       # 開機
```

### 使用 kubectl

```bash
export KUBECONFIG=$(pwd)/kubeconfig/k3s-azure.yaml
kubectl get nodes
```

### 緊急救援

若 Tailscale 連不上，使用 Azure Run Command：

```bash
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo systemctl restart tailscaled" "sudo tailscale status"
```

### 銷毀資源

```bash
terraform destroy
```

## 技術細節

| 項目 | 值 |
|------|-----|
| **雲端平台** | Azure (japaneast) |
| **VM 規格** | Standard_B2s (2 vCPU, 4 GB RAM) |
| **作業系統** | Ubuntu 22.04 LTS (Gen2) |
| **存取方式** | Tailscale SSH（無 Public SSH） |

## 疑難排解

| 問題 | 解法 |
|------|------|
| kubectl 連不上 | `tailscale status` 確認 VPN 連線 |
| VM 無法啟動 | `az vm list -d --query "[?name=='my-k3s-vm'].powerState"` |
| Terraform plan 有差異 | 檢查 OS Disk 名稱、Gen2 Image SKU |

---

**更多詳情**：[docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)

---

**建立日期:** 2026-01-27  
**最後更新:** 2026-01-31
