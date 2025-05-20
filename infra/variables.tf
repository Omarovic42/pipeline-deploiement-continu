variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "ami_id" {
  description = "AMI ID for Ubuntu"
  type        = string
  default     = "ami-007c433663055a1cc" # Ubuntu 22.04 LTS en eu-west-3
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t2.micro"
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé publique SSH"
  type        = string
  # Remplacer par le chemin absolu réel si besoin
  default     = "/root/.ssh/id_ed25519.pub"
}

variable "api_port" {
  description = "Port d'écoute de l'API"
  type        = number
  default     = 3000
}
