output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "gateway_public_ip" {
  description = "Gateway server public IP"
  value       = aws_eip.gateway.public_ip
}

output "gateway_private_ip" {
  description = "Gateway server private IP"
  value       = aws_instance.gateway.private_ip
}

output "api_services_public_ip" {
  description = "API Services server public IP"
  value       = aws_eip.api_services.public_ip
}

output "api_services_private_ip" {
  description = "API Services server private IP"
  value       = aws_instance.api_services.private_ip
}

output "storage_public_ip" {
  description = "Storage server public IP"
  value       = aws_eip.storage.public_ip
}

output "storage_private_ip" {
  description = "Storage server private IP"
  value       = aws_instance.storage.private_ip
}

output "gateway_instance_id" {
  description = "Gateway EC2 instance ID"
  value       = aws_instance.gateway.id
}

output "api_services_instance_id" {
  description = "API Services EC2 instance ID"
  value       = aws_instance.api_services.id
}

output "storage_instance_id" {
  description = "Storage EC2 instance ID"
  value       = aws_instance.storage.id
}

output "ssh_connection_commands" {
  description = "SSH connection commands for each server"
  value = {
    gateway      = "ssh -i ~/.ssh/${var.project_name}-key ubuntu@${aws_eip.gateway.public_ip}"
    api_services = "ssh -i ~/.ssh/${var.project_name}-key ubuntu@${aws_eip.api_services.public_ip}"
    storage      = "ssh -i ~/.ssh/${var.project_name}-key ubuntu@${aws_eip.storage.public_ip}"
  }
}

output "application_urls" {
  description = "Application URLs"
  value = {
    api_gateway = "http://${aws_eip.gateway.public_ip}:8082"
    health_checks = {
      gateway      = "http://${aws_eip.gateway.public_ip}:8082/health"
      product      = "http://${aws_eip.api_services.public_ip}:8080/health"
      basket       = "http://${aws_eip.api_services.public_ip}:8081/health"
    }
  }
}

output "ansible_inventory" {
  description = "Ansible inventory configuration"
  value = {
    gateway = {
      host        = aws_eip.gateway.public_ip
      private_ip  = aws_instance.gateway.private_ip
      instance_id = aws_instance.gateway.id
    }
    api_services = {
      host        = aws_eip.api_services.public_ip
      private_ip  = aws_instance.api_services.private_ip
      instance_id = aws_instance.api_services.id
    }
    storage = {
      host        = aws_eip.storage.public_ip
      private_ip  = aws_instance.storage.private_ip
      instance_id = aws_instance.storage.id
    }
  }
}
