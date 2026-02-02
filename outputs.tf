# ============================================================================
# Outputs
# ============================================================================

# Azure Outputs
output "azure_vm_name" {
  description = "Azure VM name"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "azure_vm_private_ip" {
  description = "Azure VM private IP address"
  value       = azurerm_network_interface.nic.private_ip_address
}

# AWS Outputs
output "aws_instance_id" {
  description = "AWS EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "aws_instance_private_ip" {
  description = "AWS EC2 instance private IP address"
  value       = aws_instance.k3s.private_ip
}

output "aws_instance_public_ip" {
  description = "AWS EC2 instance public IP (temporary, for initial Tailscale setup)"
  value       = aws_instance.k3s.public_ip
}

output "aws_instance_public_dns" {
  description = "AWS EC2 instance public DNS name"
  value       = aws_instance.k3s.public_dns
}

# Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ========================================
    Multi-Cloud K3s Lab Deployed!
    ========================================

    Azure VM:  ${azurerm_linux_virtual_machine.vm.name}
    AWS EC2:   ${aws_instance.k3s.id}

    Next Steps:

    1. Wait for cloud-init to complete (~2-3 minutes):

       # Azure (using Azure Run Command)
       az vm run-command invoke \
         --resource-group ${azurerm_resource_group.rg.name} \
         --name ${azurerm_linux_virtual_machine.vm.name} \
         --command-id RunShellScript \
         --scripts "tail -20 /var/log/user-data.log"

       # AWS (using console output)
       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s.id} \
         --region ${var.aws_region} | grep "Setup complete"

    2. Check Tailscale devices:
       https://login.tailscale.com/admin/machines

       You should see:
       - my-k3s-vm (Azure) ✓
       - my-k3s-vm-aws (AWS) ✓

    3. Access via Tailscale SSH:
       tailscale ssh ubuntu@my-k3s-vm       # Azure
       tailscale ssh ubuntu@my-k3s-vm-aws   # AWS

    4. Get kubeconfigs:
       # Azure
       tailscale ssh ubuntu@my-k3s-vm "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig/k3s-azure.yaml
       AZURE_TS_IP=$(tailscale ssh ubuntu@my-k3s-vm "tailscale ip -4")
       sed -i "s|https://127.0.0.1:6443|https://$AZURE_TS_IP:6443|g" kubeconfig/k3s-azure.yaml

       # AWS
       tailscale ssh ubuntu@my-k3s-vm-aws "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig/k3s-aws.yaml
       AWS_TS_IP=$(tailscale ssh ubuntu@my-k3s-vm-aws "tailscale ip -4")
       sed -i "s|https://127.0.0.1:6443|https://$AWS_TS_IP:6443|g" kubeconfig/k3s-aws.yaml

    5. Test both clusters:
       KUBECONFIG=kubeconfig/k3s-azure.yaml kubectl get nodes
       KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

    ========================================
    Troubleshooting:

    If cloud-init failed, check logs:
    - Azure: az vm run-command invoke --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_linux_virtual_machine.vm.name} --command-id RunShellScript --scripts "tail -100 /var/log/cloud-init-output.log"
    - AWS: aws ec2 get-console-output --instance-id ${aws_instance.k3s.id} --region ${var.aws_region}
    ========================================
  EOT
}
