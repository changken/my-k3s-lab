#!/bin/bash
set -euo pipefail

# ============================================================================
# AWS EC2 User Data Script
# Automatically installs and configures:
# - Tailscale VPN
# - K3s Kubernetes
# ============================================================================

# Variables (injected by Terraform)
TAILSCALE_AUTH_KEY="${tailscale_auth_key}"
HOSTNAME="${hostname}"

# Logging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "========================================="
echo "Starting user-data script at $(date)"
echo "========================================="

# Set hostname
hostnamectl set-hostname "$HOSTNAME"

# Update system
echo "[1/4] Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Tailscale
echo "[2/4] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to Tailscale network
echo "[3/4] Connecting to Tailscale network..."
systemctl enable --now tailscaled
tailscale up \
  --authkey="$TAILSCALE_AUTH_KEY" \
  --ssh \
  --hostname="$HOSTNAME" \
  --accept-routes

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo "Tailscale IP: $TAILSCALE_IP"

# Install K3s
echo "[4/4] Installing K3s..."
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$TAILSCALE_IP" \
  --node-external-ip "$TAILSCALE_IP" \
  --node-name "$HOSTNAME"

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null; do
  sleep 2
done

echo "========================================="
echo "Setup complete at $(date)"
echo "========================================="
echo "Tailscale IP: $TAILSCALE_IP"
echo "To get kubeconfig:"
echo "  tailscale ssh ubuntu@$HOSTNAME"
echo "  sudo cat /etc/rancher/k3s/k3s.yaml"
echo "========================================="
