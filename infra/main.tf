provider "aws" {
  region = var.aws_region
}

# Création d'une paire de clés SSH
#resource "aws_key_pair" "deployer" {
#  key_name   = "deployer-key"
#  public_key = file(var.ssh_public_key_path)

#  lifecycle {
#    prevent_destroy = true
#  }
#}

# Création d'un groupe de sécurité
resource "aws_security_group" "api_sg" {
  name        = "api-sg"
  description = "Security group for API server"

  # Autoriser SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Autoriser le port API
  ingress {
    from_port   = var.api_port
    to_port     = var.api_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Autoriser tout le trafic sortant
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "api-sg"
  }
}

# Création d'une instance EC2
resource "aws_instance" "api_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  tags = {
    Name = "api-server"
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3
  EOF
}

# Créer un fichier d'inventaire Ansible dynamique
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    api_ip = aws_instance.api_server.public_ip
  })
  filename = "${path.module}/../ansible/inventory.ini"

  depends_on = [aws_instance.api_server]
}
