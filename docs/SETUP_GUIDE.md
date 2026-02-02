# Multi-Cloud K3s 開發環境建置指南

本文件記錄專案的詳細建置過程，包含 Azure 和 AWS 的手動 CLI 方式與 Terraform 資源匯入，作為歷史參考。

> [!NOTE]
> 日常操作請參閱 [README.md](../README.md)

---

## 1. 手動建立環境（CLI 方式）

> 此章節為歷史記錄，說明專案最初如何以 CLI 建立。

### 1.1 Azure 資源建立

#### 建立 Azure 資源

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

#### 安裝 Tailscale 與 K3s (Azure)

```bash
# 透過 Tailscale SSH 進入 VM 後執行
TS_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP
```

### 1.2 AWS 資源建立

#### 建立 AWS 資源

```bash
# 產生 repo-local SSH Key
ssh-keygen -t ed25519 -f ./.ssh/aws_emergency_ed25519 -N ""

# 設定變數
AWS_REGION="us-east-1"
KEY_NAME="my-k3s-lab-emergency-key"

# 匯入 SSH public key
aws ec2 import-key-pair \
  --key-name "$KEY_NAME" \
  --public-key-material fileb://./.ssh/aws_emergency_ed25519.pub \
  --region "$AWS_REGION"

# 建立 VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=my-k3s-lab-vpc}]' \
  --region "$AWS_REGION" \
  --query 'Vpc.VpcId' --output text)

# 建立 Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=my-k3s-lab-igw}]' \
  --region "$AWS_REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
  --vpc-id "$VPC_ID" \
  --internet-gateway-id "$IGW_ID" \
  --region "$AWS_REGION"

# 建立 Subnet
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.1.1.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=my-k3s-lab-subnet}]' \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)

# 建立 Route Table 並設定路由
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=my-k3s-lab-rt}]' \
  --region "$AWS_REGION" \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" \
  --region "$AWS_REGION"

aws ec2 associate-route-table \
  --subnet-id "$SUBNET_ID" \
  --route-table-id "$RTB_ID" \
  --region "$AWS_REGION"

# 建立 Security Group
SG_ID=$(aws ec2 create-security-group \
  --group-name my-k3s-lab-sg \
  --description "Security group for K3s node (Tailscale-first)" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

# 允許所有 outbound 流量
aws ec2 authorize-security-group-egress \
  --group-id "$SG_ID" \
  --protocol all \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"

# 取得最新 Ubuntu 24.04 AMI ID
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=state,Values=available" \
  --region "$AWS_REGION" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

# 建立 EC2 Instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.medium \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-k3s-vm-aws}]' \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Created EC2 Instance: $INSTANCE_ID"
```

#### 安裝 Tailscale 與 K3s (AWS)

```bash
# 透過 SSH 連入 EC2（需等待實例啟動）
# 或使用 EC2 Instance Connect

# 安裝 Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled

# 加入 Tailnet
sudo tailscale up --authkey=tskey-auth-REPLACE_ME --ssh --hostname=my-k3s-vm-aws

# 安裝 K3s
TS_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$TS_IP" \
  --node-external-ip "$TS_IP" \
  --node-name my-k3s-vm-aws
```

---

## 2. Terraform 資源匯入

若要將現有資源導入 Terraform 管理：

### 2.1 Azure 資源匯入

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

### 2.2 AWS 資源匯入

```bash
# 設定 AWS region
export AWS_REGION="us-east-1"

# 初始化（如果尚未執行）
terraform init

# 匯入 VPC
terraform import aws_vpc.main vpc-xxxxx

# 匯入 Internet Gateway
terraform import aws_internet_gateway.main igw-xxxxx

# 匯入 Subnet
terraform import aws_subnet.main subnet-xxxxx

# 匯入 Route Table
terraform import aws_route_table.main rtb-xxxxx

# 匯入 Route Table Association
terraform import aws_route_table_association.main subnet-xxxxx/rtb-xxxxx

# 匯入 Security Group
terraform import aws_security_group.k3s sg-xxxxx

# 匯入 Key Pair
terraform import aws_key_pair.emergency my-k3s-lab-emergency-key

# 匯入 EC2 Instance
terraform import aws_instance.k3s i-xxxxx
```

**提示**：使用以下指令查詢資源 ID：

```bash
# 查詢 VPC ID
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-k3s-lab-vpc" --query 'Vpcs[0].VpcId' --output text

# 查詢 Instance ID
aws ec2 describe-instances --filters "Name=tag:Name,Values=my-k3s-vm-aws" --query 'Reservations[0].Instances[0].InstanceId' --output text
```

---

## 3. Terraform Cloud 設定

1. 前往 [Terraform Cloud](https://app.terraform.io) 註冊/登入
2. 建立 Organization 和 Workspace
3. **重要**：Workspace Settings → General → Execution Mode 選擇 `Local`
4. 執行 `terraform login` 完成認證

---

## 4. 常見問題

### 4.1 Azure 相關

| 問題 | 解法 |
|------|------|
| OS Disk 名稱不符 | 在 `main.tf` 中指定完整 disk 名稱 |
| Trusted Launch | 確保 `secure_boot_enabled = true`, `vtpm_enabled = true` |
| Image 不符 | 確認使用 `ubuntu-24_04-lts` offer |
| Azure CLI 未登入 | 執行 `az login` |

### 4.2 AWS 相關

| 問題 | 解法 |
|------|------|
| AMI ID 變動 | 使用 `data.aws_ami` 動態查詢最新 AMI |
| User data 未執行 | 檢查 `/var/log/cloud-init-output.log` |
| EC2 無法連 Tailscale | 確認 Security Group 允許 outbound 0.0.0.0/0 |
| AWS CLI 未配置 | 執行 `aws configure` |
| 權限不足 | 確認 IAM user 有足夠權限（EC2, VPC 相關） |

### 4.3 Terraform 相關

| 問題 | 解法 |
|------|------|
| State 衝突 | 確認 Terraform Cloud workspace 設定為 Local execution |
| Provider 版本衝突 | 執行 `terraform init -upgrade` |
| 變數未定義 | 檢查 `terraform.tfvars` 是否包含所有必要變數 |

---

## 5. 多雲架構注意事項

### 5.1 網路架構

```
┌─────────────────────────┐          ┌─────────────────────────┐
│   Azure (japaneast)     │          │   AWS (us-east-1)       │
│                         │          │                         │
│  my-k3s-vm              │          │  my-k3s-vm-aws          │
│  ├─ Private: 10.0.0.4   │          │  ├─ Private: 10.1.1.x   │
│  └─ Tailscale: 100.x.y  │◄────────►│  └─ Tailscale: 100.a.b  │
│                         │ Mesh VPN │                         │
│  K3s: 6443              │          │  K3s: 6443              │
└─────────────────────────┘          └─────────────────────────┘
```

### 5.2 成本優化

| 項目 | Azure | AWS | 說明 |
|------|-------|-----|------|
| **計算** | Standard_B2s | t3.medium | 相似規格 |
| **關機省費** | `az vm deallocate` | `aws ec2 stop-instances` | 停機時不收取計算費用 |
| **儲存費用** | 繼續收費 | 繼續收費 | EBS/Disk 費用持續 |
| **月費估算** | ~$30 | ~$30 | 假設 24/7 運行 |

### 5.3 備份與災難恢復

```bash
# 定期備份 kubeconfig
cp kubeconfig/k3s-azure.yaml kubeconfig/k3s-azure.yaml.$(date +%Y%m%d)
cp kubeconfig/k3s-aws.yaml kubeconfig/k3s-aws.yaml.$(date +%Y%m%d)

# 使用 Git 追蹤 Terraform 配置（但排除 .tfvars）
git add *.tf
git commit -m "Update infrastructure configuration"
```

## 6. 參考資料

- [K3s 官方文件](https://docs.k3s.io/)
- [Tailscale 官方文件](https://tailscale.com/kb/)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cloud-init 文件](https://cloudinit.readthedocs.io/)
