variable "location" {
  description = "Azure Region"
  default     = "japaneast"
}

variable "resource_group_name" {
  description = "Resource Group Name"
  default     = "my-k3s-tf-rg"
}

variable "tailscale_auth_key" {
  description = "Tailscale Auth Key (starts with tskey-...)"
  type        = string
  sensitive   = true
}
