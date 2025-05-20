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

output "api_server_public_ip" {
  description = "Adresse IP publique du serveur API"
  value       = aws_instance.api_server.public_ip
}

output "key_pair_name" {
  description = "Nom de la paire de clés SSH utilisée"
  value       = aws_key_pair.deployer.key_name
}

output "ansible_inventory_path" {
  description = "Chemin du fichier d'inventaire Ansible généré"
  value       = local_file.ansible_inventory.filename
}
