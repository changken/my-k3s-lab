# ============================================================================
# Common Variables
# ============================================================================

variable "tailscale_auth_key" {
  description = "Tailscale authentication key for automatic VPN enrollment"
  type        = string
  sensitive   = true
}

# ============================================================================
# Azure Variables
# ============================================================================

variable "emergency_ssh_public_key_path" {
  description = "Path to emergency SSH public key for Azure VM access"
  type        = string
}

# ============================================================================
# AWS Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for EC2 instance"
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "AWS EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "aws_ssh_public_key_path" {
  description = "Path to emergency SSH public key for AWS EC2 access"
  type        = string
  default     = "./.ssh/aws_emergency_ed25519.pub"
}

variable "aws_availability_zone" {
  description = "AWS availability zone for EC2 instance"
  type        = string
  default     = ""  # Empty means AWS will auto-select
}
