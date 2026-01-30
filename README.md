# My K3s Lab on Azure

這是一個使用 Terraform 管理的 K3s 開發環境，部署在 Azure VM 上，並透過 Tailscale VPN 進行安全的遠端管理。

## ⚠️ 免責聲明

> **本專案僅供個人學習與實驗用途，不建議直接用於生產環境。**  
> **使用者需自行承擔所有風險，包括但不限於 Azure 服務費用、資料安全與服務穩定性。**  
> **作者不對任何因使用本專案而產生的損失負責。**

## 專案結構

```
my-k3s-lab/
├── README.md                    # 本檔案
├── main.tf                      # Terraform 主配置
├── terraform.tfvars.example     # 變數範例檔（可公開）
├── .terraform.lock.hcl          # Terraform provider 鎖定檔
├── .gitignore                   # Git 忽略規則
│
├── kubeconfig/                  # Kubernetes 配置檔（敏感，已忽略）
│   └── k3s-azure.yaml           # K3s cluster kubeconfig
│
├── docs/                        # 文檔目錄
│   └── SETUP_GUIDE.md           # 完整建置指南
│
├── scripts/                     # 工具腳本
│   └── import_resources.sh      # 導入現有 Azure 資源到 Terraform
│
└── archive/                     # 歷史版本備份
    └── deprecated_create_new_k3s/
```

## 快速開始

### 前置需求

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 已登入
- [Tailscale](https://tailscale.com/) 帳號
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (選用)

### 1. Clone 專案並配置變數

```bash
# Clone 專案
git clone <your-repo-url>
cd my-k3s-lab

# 建立 repo-local SSH key（備援用，避免汙染 ~/.ssh）
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# 複製範例變數檔案
cp terraform.tfvars.example terraform.tfvars

# 編輯變數檔案
# - emergency_ssh_public_key_path 指向 repo-local 公鑰
# - backup_ssh_enabled 預設 false（需要備援時再開）
# - backup_ssh_source_cidr 改成你的家用 CIDR
vim terraform.tfvars
```

### 2. 設定 Terraform Cloud Backend

```bash
# 註冊 Terraform Cloud: https://app.terraform.io/signup/account
# 建立 Organization: changkenkai
# 建立 Workspace: my-k3s-lab (CLI-driven workflow)
# ⚠️ 重要：在 Workspace Settings → General → Execution Mode 選擇 "Local"

# 登入 Terraform Cloud
terraform login

# 初始化 Terraform
terraform init
```

### 3. 部署基礎設施

```bash
# 檢查變更計畫
terraform plan

# 執行部署
terraform apply
```

### 4. 配置 Tailscale（首次部署）

部署完成後，VM 尚未加入 Tailscale。建議使用 Azure Run Command 完成安裝與登入：

```bash
# 安裝 Tailscale 並啟動服務
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

接著使用 Tailscale SSH 進入 VM 進行後續操作：

```bash
tailscale ssh ubuntu@my-k3s-vm

# 取得 Tailscale IP
tailscale ip -4

# 更新 K3s TLS SAN（使用 Tailscale IP）
TS_IP=$(tailscale ip -4)
sudo systemctl stop k3s
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP

# 下載 kubeconfig
sudo cat /etc/rancher/k3s/k3s.yaml
```

### 5. 本地配置 kubectl

```bash
# 將上述 kubeconfig 內容存到本地
vim kubeconfig/k3s-azure.yaml

# 修改 server IP 為 Tailscale IP
# server: https://<TAILSCALE_IP>:6443

# 設定環境變數
export KUBECONFIG=$(pwd)/kubeconfig/k3s-azure.yaml

# 測試連線
kubectl get nodes
```

## 日常操作

### 關機/開機（省費用）

```bash
# 關機（停止計費 CPU/Memory）
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm

# 開機
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm

# 等待 1-2 分鐘後，Tailscale 和 K3s 會自動啟動
kubectl get nodes
```

### 更新基礎設施

```bash
# 修改 main.tf 後
terraform plan
terraform apply
```

### 備援 SSH（必要時）

```bash
# 在 terraform.tfvars 中暫時打開備援 SSH
# backup_ssh_enabled = true
# backup_ssh_source_cidr = "<YOUR_HOME_CIDR>"

terraform apply

# 使用 repo-local key（不寫入 ~/.ssh）
ssh -F /dev/null -i ./.ssh/azure_emergency_ed25519 -o UserKnownHostsFile=./.ssh/known_hosts -o StrictHostKeyChecking=accept-new ubuntu@<VM_PUBLIC_IP>

# 修復後關回
# backup_ssh_enabled = false
terraform apply
```

### 銷毀所有資源

```bash
# ⚠️ 警告：這會刪除所有資源，包含資料
terraform destroy
```

## 技術細節

| 項目 | 值 |
|------|-----|
| **雲端平台** | Azure (japaneast) |
| **VM 規格** | Standard_B2s (2 vCPU, 4 GB RAM) |
| **作業系統** | Ubuntu 22.04 LTS (Gen2) |
| **K3s 版本** | latest |
| **Tailscale IP** | 100.90.81.87 |
| **Public IP** | Static (保留) |
| **State 儲存** | Terraform Cloud |

## 安全性

- ✅ Terraform State 儲存在 Terraform Cloud（加密）
- ✅ Kubeconfig 已加入 `.gitignore`
- ✅ SSH 使用公鑰認證（密碼已停用）
- ✅ Tailscale Auth Key 不進 Terraform state（手動登入）
- ✅ Azure Subscription ID 使用環境變數

## 參考文檔

- [完整建置指南](docs/SETUP_GUIDE.md)

## 疑難排解

### kubectl 連不上

```bash
# 確認 Tailscale 連線
tailscale status

# 確認 VM 是否啟動
az vm list -d --query "[?name=='my-k3s-vm'].powerState" -o tsv

# Tailscale SSH 進 VM 檢查 K3s
tailscale ssh ubuntu@<TAILSCALE_IP>
sudo systemctl status k3s
```

### Terraform Cloud 遷移失敗

```bash
# 重設本地 backend
rm -rf .terraform
terraform init -migrate-state
```

---

**建立日期:** 2026-01-27  
**最後更新:** 2026-01-27
