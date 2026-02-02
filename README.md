# Multi-Cloud K3s Lab (Azure + AWS)

這是一個使用 Terraform 管理的多雲 K3s 開發環境，同時部署在 Azure VM 和 AWS EC2 上，並透過 Tailscale VPN 進行安全的遠端管理。

## ⚠️ 免責聲明

> **本專案僅供個人學習與實驗用途，不建議直接用於生產環境。**
> **使用者需自行承擔所有風險，包括但不限於雲端服務費用、資料安全與服務穩定性。**
> **作者不對任何因使用本專案而產生的損失負責。**

## 專案結構

```
my-k3s-lab/
├── main.tf                      # Terraform Cloud 與 Azure 資源配置
├── aws.tf                       # AWS EC2 + VPC 資源
├── variables.tf                 # 變數定義（Azure + AWS + Tailscale）
├── outputs.tf                   # 輸出資訊
├── user-data-aws.sh             # AWS EC2 初始化腳本（自動安裝 Tailscale + K3s）
├── terraform.tfvars.example     # 變數範例檔（可公開）
├── docs/SETUP_GUIDE.md          # 詳細建置記錄
└── kubeconfig/
    ├── k3s-azure.yaml           # Azure K3s kubeconfig（已忽略）
    └── k3s-aws.yaml             # AWS K3s kubeconfig（已忽略）
```

## 快速開始

### 前置需求

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 已登入
- [AWS CLI](https://aws.amazon.com/cli/) 已配置（`aws configure`）
- [Tailscale](https://tailscale.com/) 帳號
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### 1. 初始化專案

```bash
git clone <your-repo-url>
cd my-k3s-lab

# 產生 repo-local SSH 金鑰
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""
ssh-keygen -t ed25519 -f ./.ssh/aws_emergency_ed25519 -N ""

# 設定變數
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 Tailscale auth key 和其他設定
```

### 2. 配置 Terraform Cloud

前往 [Terraform Cloud](https://app.terraform.io) 設定 workspace：

1. **Settings → General → Execution Mode** 選擇 **Local**
2. 這樣可以使用本機的 Azure/AWS CLI 憑證

### 3. 部署資源

```bash
terraform login   # 登入 Terraform Cloud
terraform init
terraform plan    # 確認計畫（應該顯示 "X to add, 0 to change, 0 to destroy"）
terraform apply
```

### 4. 等待自動配置完成

> 🎉 Azure 和 AWS 都會透過 cloud-init 自動安裝 Tailscale 和 K3s！

```bash
# 檢查 Terraform 輸出（包含詳細指示）
terraform output next_steps

# 等待 cloud-init 完成（約 2-3 分鐘）
# Azure
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "tail -20 /var/log/user-data.log"

# AWS
aws ec2 get-console-output \
  --instance-id $(terraform output -raw aws_instance_id) | grep "Setup complete"
```

### 5. 驗證 Tailscale 連線

前往 https://login.tailscale.com/admin/machines

應該看到：
- ✅ `my-k3s-vm` (Azure)
- ✅ `my-k3s-vm-aws` (AWS)

### 6. 取得 Kubeconfig

```bash
# Azure
tailscale ssh ubuntu@my-k3s-vm "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig/k3s-azure.yaml
AZURE_TS_IP=$(tailscale ssh ubuntu@my-k3s-vm "tailscale ip -4")
sed -i "s|https://127.0.0.1:6443|https://$AZURE_TS_IP:6443|g" kubeconfig/k3s-azure.yaml

# AWS
tailscale ssh ubuntu@my-k3s-vm-aws "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig/k3s-aws.yaml
AWS_TS_IP=$(tailscale ssh ubuntu@my-k3s-vm-aws "tailscale ip -4")
sed -i "s|https://127.0.0.1:6443|https://$AWS_TS_IP:6443|g" kubeconfig/k3s-aws.yaml
```

### 7. 驗證集群

```bash
# 測試 Azure 集群
KUBECONFIG=kubeconfig/k3s-azure.yaml kubectl get nodes

# 測試 AWS 集群
KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes
```

## 日常操作

### 關機/開機（節省費用）

```bash
# Azure VM
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm  # 關機
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm       # 開機

# AWS EC2
aws ec2 stop-instances --instance-ids $(terraform output -raw aws_instance_id)      # 關機
aws ec2 start-instances --instance-ids $(terraform output -raw aws_instance_id)     # 開機
```

### 使用 kubectl

```bash
# 單一集群
export KUBECONFIG=$(pwd)/kubeconfig/k3s-azure.yaml
kubectl get nodes

# 或指定 AWS
export KUBECONFIG=$(pwd)/kubeconfig/k3s-aws.yaml
kubectl get nodes

# 同時管理兩個集群
export KUBECONFIG=$(pwd)/kubeconfig/k3s-azure.yaml:$(pwd)/kubeconfig/k3s-aws.yaml
kubectl config get-contexts
kubectl config use-context default  # 切換集群
```

### 緊急救援

若 Tailscale 連不上：

```bash
# Azure: 使用 Azure Run Command
az vm run-command invoke \
  --resource-group my-k3s-lab-rg --name my-k3s-vm \
  --command-id RunShellScript \
  --scripts "sudo systemctl restart tailscaled" "sudo tailscale status"

# AWS: 使用 EC2 Instance Connect 或 Systems Manager Session Manager
aws ec2-instance-connect send-ssh-public-key \
  --instance-id $(terraform output -raw aws_instance_id) \
  --instance-os-user ubuntu \
  --ssh-public-key file://.ssh/aws_emergency_ed25519.pub
```

### 查看費用

```bash
# Azure 費用
az consumption usage list --start-date 2026-02-01 --end-date 2026-02-28

# AWS 費用
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

### 銷毀資源

```bash
terraform destroy  # 同時刪除 Azure 和 AWS 資源
```

## 技術細節

### Azure 節點

| 項目 | 值 |
|------|-----|
| **雲端平台** | Azure East Japan (japaneast) |
| **VM 規格** | Standard_B2s (2 vCPU, 4 GB RAM) |
| **作業系統** | Ubuntu 24.04 LTS |
| **存取方式** | Tailscale SSH（無 Public SSH） |
| **自動配置** | Cloud-init (Tailscale + K3s) |
| **預估費用** | ~$30/月 |

### AWS 節點

| 項目 | 值 |
|------|-----|
| **雲端平台** | AWS US East 1 (us-east-1) |
| **EC2 規格** | t3.medium (2 vCPU, 4 GB RAM) |
| **作業系統** | Ubuntu 24.04 LTS |
| **存取方式** | Tailscale SSH（無 Public SSH） |
| **自動配置** | Cloud-init (Tailscale + K3s) |
| **預估費用** | ~$30/月 |

### 共通架構

- **網路**: 兩個獨立的 K3s 集群，透過 Tailscale Mesh VPN 互連
- **安全**: 無公開 SSH port，僅透過 Tailscale 存取
- **自動化**: Cloud-init 自動配置（Tailscale + K3s）
- **IaC**: Terraform 統一管理，Local execution mode
- **State**: 儲存在 Terraform Cloud

## 疑難排解

| 問題 | 解法 |
|------|------|
| kubectl 連不上 | `tailscale status` 確認 VPN 連線 |
| Azure VM 無法啟動 | `az vm list -d --query "[?name=='my-k3s-vm'].powerState"` |
| AWS EC2 無法啟動 | `aws ec2 describe-instances --instance-ids $(terraform output -raw aws_instance_id)` |
| Azure K3s 未自動安裝 | `az vm run-command invoke --resource-group my-k3s-lab-rg --name my-k3s-vm --command-id RunShellScript --scripts "tail -100 /var/log/user-data.log"` |
| AWS K3s 未自動安裝 | `aws ec2 get-console-output --instance-id $(terraform output -raw aws_instance_id)` 查看 cloud-init 日誌 |
| Terraform plan 顯示差異 | 檢查 OS Disk 名稱、Gen2 Image SKU、AMI ID |
| Tailscale 連不上 | 檢查 Security Group (AWS) 或 NSG (Azure) 是否允許 outbound |

---

**更多詳情**：[docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)

---

**建立日期:** 2026-01-27
**最後更新:** 2026-02-02 (新增 AWS 多雲支援)
