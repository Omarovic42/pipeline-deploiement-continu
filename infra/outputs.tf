output "instance_ip" {
  description = "Adresse IP publique de l'instance EC2"
  value       = aws_instance.api_server.public_ip
}

output "instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.api_server.id
}

output "security_group_id" {
  description = "ID du groupe de sécurité"
  value       = aws_security_group.api_sg.id
}
