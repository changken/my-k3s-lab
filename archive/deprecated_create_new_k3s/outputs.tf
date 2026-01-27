output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  value = "ssh ubuntu@${azurerm_public_ip.pip.ip_address}"
}

output "next_steps" {
  value = <<EOT
  
  1. SSH into the VM: ssh ubuntu@${azurerm_public_ip.pip.ip_address}
  2. Verify K3s: sudo kubectl get nodes
  3. Download kubeconfig: scp ubuntu@${azurerm_public_ip.pip.ip_address}:~/k3s.yaml ./k3s-tf.yaml
  4. Edit IP in k3s-tf.yaml to the Tailscale IP.
  EOT
}
