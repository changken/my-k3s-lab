# [封存] 方案 A：自動化全新建立腳本

此目錄存放原本規劃用於「一鍵開機並自動配置」的代碼。

## 內容說明
- `cloud-init.yaml`: 包含自動安裝 Tailscale、登入 VPN、獲取 IP 並安裝 K3s 的完整自動化邏輯。
- `main.tf`: 包含 `custom_data` 注入邏輯的 Terraform 配置。

## 為何封存？
目前的專案已轉為納管（Import）手動建立的資源。此目錄僅作為未來需要「橫向擴展」或「重新建立環境」時的指令參考。

## 參考：如何啟用
若要使用此方案建立新環境：
1. 進入此目錄。
2. 準備 Tailscale Auth Key。
3. `terraform apply -var="tailscale_auth_key=tskey-auth-..."`
