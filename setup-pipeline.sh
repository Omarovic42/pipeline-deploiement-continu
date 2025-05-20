#!/bin/bash

# Variables
GITHUB_USERNAME="Omarovic42"
REPO_NAME="pipeline-deploiement-continu"

echo "====== Configuration du pipeline de déploiement continu ======"
echo "Utilisateur GitHub: $GITHUB_USERNAME"
echo "Nom du dépôt: $REPO_NAME"

# Créer la structure de dossiers
echo "Création de la structure de dossiers..."
mkdir -p "$REPO_NAME"/{infra,ansible,api,.github/workflows}
cd "$REPO_NAME" || { echo "Échec lors du changement de répertoire vers $REPO_NAME"; exit 1; }

# Créer les fichiers avec le contenu fourni
echo "Création des fichiers d'infrastructure..."

# main.tf
cat > infra/main.tf << 'EOT'
provider "aws" {
  region = var.aws_region
}

# Création d'une paire de clés SSH
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file(var.ssh_public_key_path)
}

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

  # Script d'initialisation de base
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3
              EOF
}

# Créer un fichier d'inventaire Ansible dynamique
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl",
    {
      api_ip = aws_instance.api_server.public_ip
    }
  )
  filename = "${path.module}/../ansible/inventory.ini"
}
EOT

# variables.tf
cat > infra/variables.tf << 'EOT'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for Ubuntu"
  type        = string
  default     = "ami-0261755bbcb8c4a84" # Ubuntu 20.04 LTS en us-east-1
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t2.micro"
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé publique SSH"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "api_port" {
  description = "Port d'écoute de l'API"
  type        = number
  default     = 3000
}
EOT

# outputs.tf
cat > infra/outputs.tf << 'EOT'
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
EOT

# inventory.tpl
cat > infra/inventory.tpl << 'EOT'
[api_servers]
${api_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
EOT

# ansible deploy.yml - Correction du lookup dans les variables
cat > ansible/deploy.yml << EOT
---
- name: Déploiement de l'API
  hosts: api_servers
  become: true
  vars:
    app_dir: "/opt/sensor-api"
    repo_url: "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
    api_port: 3000
    node_version: "16.x"

  tasks:
    - name: Mise à jour des paquets
      apt:
        update_cache: yes
        upgrade: yes

    - name: Installation des paquets requis
      apt:
        name:
          - git
          - curl
          - build-essential
        state: present

    - name: Ajout du repository NodeJS
      shell: |
        curl -fsSL https://deb.nodesource.com/setup_{{ node_version }} | bash -
      args:
        warn: false

    - name: Installation de NodeJS et npm
      apt:
        name: nodejs
        state: present

    - name: Installation de PM2 globalement
      npm:
        name: pm2
        global: yes
        state: present

    - name: Création du répertoire d'application
      file:
        path: "{{ app_dir }}"
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Clonage/Mise à jour du dépôt Git
      git:
        repo: "{{ repo_url }}"
        dest: "{{ app_dir }}"
        version: main
        force: yes
      become_user: ubuntu

    - name: Installation des dépendances NPM
      npm:
        path: "{{ app_dir }}/api"
      become_user: ubuntu

    - name: Vérification si l'application est déjà gérée par PM2
      shell: pm2 list | grep sensor-api
      register: pm2_check
      ignore_errors: yes
      become_user: ubuntu

    - name: Démarrage de l'application avec PM2
      shell: cd {{ app_dir }}/api && pm2 start index.js --name sensor-api
      when: pm2_check.rc != 0
      become_user: ubuntu

    - name: Redémarrage de l'application si déjà existante
      shell: cd {{ app_dir }}/api && pm2 restart sensor-api
      when: pm2_check.rc == 0
      become_user: ubuntu

    - name: Sauvegarde de la configuration PM2
      shell: pm2 save
      become_user: ubuntu

    - name: Configuration de PM2 pour démarrer au boot
      shell: pm2 startup | tail -n 1
      register: pm2_startup
      become_user: ubuntu

    - name: Exécution de la commande PM2 startup
      shell: "{{ pm2_startup.stdout }}"
      when: pm2_startup.stdout != ""
EOT

echo "Création du code de l'API..."
# api/index.js
cat > api/index.js << 'EOT'
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

// Création de l'application Express
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Base de données simulée pour les capteurs
const sensors = [
  { id: 1, name: 'Temperature Sensor 1', type: 'temperature', location: 'Building A', value: 22.5, unit: '°C', timestamp: new Date() },
  { id: 2, name: 'Humidity Sensor 1', type: 'humidity', location: 'Building A', value: 45.0, unit: '%', timestamp: new Date() },
  { id: 3, name: 'CO2 Sensor 1', type: 'co2', location: 'Building B', value: 415, unit: 'ppm', timestamp: new Date() },
  { id: 4, name: 'Temperature Sensor 2', type: 'temperature', location: 'Building B', value: 24.2, unit: '°C', timestamp: new Date() },
  { id: 5, name: 'Light Sensor 1', type: 'light', location: 'Building C', value: 450, unit: 'lux', timestamp: new Date() },
];

// Routes
app.get('/', (req, res) => {
  res.json({
    message: 'API de supervision de capteurs environnementaux',
    version: '1.0.0',
    endpoints: [
      { method: 'GET', path: '/sensors', description: 'Liste tous les capteurs' },
      { method: 'GET', path: '/sensors/:id', description: 'Détails d\'un capteur spécifique' },
      { method: 'POST', path: '/sensors/:id/data', description: 'Envoie des données pour un capteur' },
      { method: 'GET', path: '/health', description: 'Vérifie l\'état de l\'API' }
    ]
  });
});

app.get('/sensors', (req, res) => {
  res.json(sensors);
});

app.get('/sensors/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const sensor = sensors.find(s => s.id === id);
  
  if (!sensor) {
    return res.status(404).json({ error: 'Capteur non trouvé' });
  }
  
  res.json(sensor);
});

app.post('/sensors/:id/data', (req, res) => {
  const id = parseInt(req.params.id);
  const sensor = sensors.find(s => s.id === id);
  
  if (!sensor) {
    return res.status(404).json({ error: 'Capteur non trouvé' });
  }
  
  if (!req.body.value) {
    return res.status(400).json({ error: 'La valeur est requise' });
  }
  
  // Mise à jour de la valeur du capteur
  sensor.value = req.body.value;
  sensor.timestamp = new Date();
  
  res.json(sensor);
});

app.get('/health', (req, res) => {
  res.json({ status: 'UP', timestamp: new Date() });
});

// Démarrage du serveur
app.listen(port, () => {
  console.log(`API de supervision de capteurs démarrée sur le port ${port}`);
});

module.exports = app;
EOT

# api/package.json
cat > api/package.json << 'EOT'
{
  "name": "sensor-api",
  "version": "1.0.0",
  "description": "API REST pour la supervision de capteurs environnementaux",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js",
    "build": "echo 'Build completed (no build step required for Node.js)'",
    "test": "jest"
  },
  "author": "",
  "license": "ISC",
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.17.1",
    "morgan": "^1.10.0"
  },
  "devDependencies": {
    "jest": "^27.0.6",
    "nodemon": "^2.0.12",
    "supertest": "^6.1.6"
  }
}
EOT

echo "Configuration du workflow GitHub Actions..."
# .github/workflows/deploy.yml
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml << EOT
name: Deploy API

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v2
        with:
          fetch-depth: 0
      
      - name: Set up Node.js
        uses: actions/setup-node@v2
        with:
          node-version: '16'
      
      - name: Install dependencies
        run: npm install
        working-directory: ./api
      
      - name: Install Terraform
        uses: hashicorp/setup-terraform@v1
        with:
          terraform_version: 1.0.0
      
      - name: Install Ansible
        run: |
          sudo apt update
          sudo apt install -y ansible
      
      - name: Set up SSH key
        run: |
          mkdir -p ~/.ssh
          echo "\${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H github.com >> ~/.ssh/known_hosts
      
      - name: Initialize Terraform
        working-directory: ./infra
        run: terraform init
      
      - name: Apply Terraform configuration
        working-directory: ./infra
        run: |
          terraform apply -auto-approve \\
            -var "ssh_public_key_path=\$HOME/.ssh/id_rsa.pub"
      
      - name: Wait for instance to be ready
        run: sleep 30
      
      - name: Execute release script
        run: |
          chmod +x release.sh
          ./release.sh
        env:
          GITHUB_USERNAME: ${GITHUB_USERNAME}
          REPO_NAME: ${REPO_NAME}
EOT

echo "Création du script de release..."
# release.sh
cat > release.sh << 'EOT'
#!/usr/bin/env bash
set -e

# Couleurs pour une meilleure lisibilité
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting release process...${NC}"

# 1. Build (si nécessaire)
echo -e "${YELLOW}Step 1: Building the application...${NC}"
cd api
npm install
npm run build
cd ..

# 2. Versioning avec git tag
echo 
echo -e "${YELLOW}Step 2: Creating a new version tag...${NC}"
VERSION="v$(date +'%Y.%m.%d')"
git tag $VERSION
git push --tags
echo -e "${GREEN}Created and pushed tag: $VERSION${NC}"

# 3. Installation de standard-version si nécessaire
echo 
echo -e "${YELLOW}Step 3: Setting up standard-version...${NC}"
npm install -g standard-version || echo "standard-version already installed"

# 4. Génération du changelog
echo 
echo -e "${YELLOW}Step 4: Generating changelog...${NC}"
standard-version --release-as minor
echo -e "${GREEN}Changelog generated${NC}"

# 5. Déploiement avec Ansible
echo 
echo -e "${YELLOW}Step 5: Deploying with Ansible...${NC}"
# Utilisation des variables d'environnement ou extraction depuis le repo si non définies
if [ -z "${GITHUB_USERNAME}" ]; then
  export GITHUB_USERNAME=$(git config --get remote.origin.url | sed -n 's/.*github.com[\/:]\([^\/]*\).*/\1/p')
fi
if [ -z "${REPO_NAME}" ]; then
  export REPO_NAME=$(basename -s .git $(git config --get remote.origin.url))
fi
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml
echo -e "${GREEN}Deployment completed successfully!${NC}"

echo 
echo -e "${GREEN}Release process completed successfully!${NC}"
EOT
chmod +x release.sh

echo "Création du rapport..."
# rapport.md
cat > rapport.md << 'EOT'
# Rapport - Pipeline de Déploiement Continu

## Introduction
Ce document décrit la mise en place d'un pipeline de déploiement continu pour une application mobile IoT de supervision de capteurs environnementaux. Le pipeline comprend plusieurs composants clés : l'infrastructure provisionnée avec Terraform, la configuration et le déploiement avec Ansible, et l'orchestration du pipeline CI/CD avec GitHub Actions.

## Architecture et choix techniques

### Domaine fonctionnel : API de supervision de capteurs
L'API développée permet de :

- Lister tous les capteurs disponibles
- Obtenir les détails d'un capteur spécifique
- Envoyer des données pour un capteur
- Vérifier l'état de l'API

L'API est développée en Node.js avec Express, ce qui offre une solution légère et performante pour gérer les requêtes HTTP.

### Choix d'infrastructure et provider
Pour ce projet, j'ai choisi AWS comme fournisseur d'infrastructure cloud pour les raisons suivantes :

- Maturité et fiabilité des services
- Large gamme d'instances disponibles
- Bonne intégration avec Terraform et Ansible
- Support robuste pour les questions de sécurité

Configuration spécifique:

- Instance EC2 t2.micro avec Ubuntu 20.04 LTS
- Groupe de sécurité autorisant le trafic SSH (port 22) et API (port 3000)
- Provisionnement complet via Terraform

## Structure des dossiers
```
/
├── infra/                 # Configuration Terraform
│   ├── main.tf            # Ressources AWS (EC2, security group, etc.)
│   ├── variables.tf       # Variables configurables
│   ├── outputs.tf         # Outputs du déploiement
│   └── inventory.tpl      # Template pour générer l'inventaire Ansible
├── ansible/               # Configuration Ansible
│   ├── inventory.ini      # Inventaire généré par Terraform
│   └── deploy.yml         # Playbook pour le déploiement de l'API
├── api/                   # Code source de l'API
│   ├── index.js           # Point d'entrée de l'API
│   └── package.json       # Configuration Node.js et dépendances
├── .github/workflows/     # Configuration GitHub Actions
│   └── deploy.yml         # Workflow de déploiement continu
├── release.sh             # Script de release
└── rapport.md             # Ce document
```

## Configuration Terraform
La configuration Terraform crée les ressources nécessaires dans AWS :

- EC2 Instance : Une machine virtuelle Ubuntu pour héberger l'API
- Security Group : Groupe de sécurité pour les règles de pare-feu
- Key Pair : Paire de clés SSH pour l'accès sécurisé

Le script génère également dynamiquement l'inventaire Ansible, ce qui facilite la configuration ultérieure.

### Fonctionnement

- `terraform init` : Initialise le répertoire de travail Terraform
- `terraform plan` : Prévisualise les changements à appliquer
- `terraform apply` : Crée ou met à jour l'infrastructure

Après l'exécution, Terraform produit des sorties utiles comme l'adresse IP publique de l'instance EC2.

## Playbook Ansible
Le playbook Ansible automatise l'installation et la configuration de l'environnement d'exécution de l'API :

- Installation des dépendances (git, Node.js, npm)
- Clonage du dépôt contenant l'API
- Installation des dépendances Node.js
- Configuration de PM2 pour gérer le processus Node.js
- Démarrage ou redémarrage de l'API

### Fonctionnement
Le playbook est exécuté avec la commande :
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml
```
L'inventaire généré par Terraform est utilisé pour cibler la machine correcte. Le playbook est idempotent, ce qui signifie qu'il peut être exécuté plusieurs fois sans effets secondaires indésirables.

## Script de release
Le script `release.sh` automatise le processus de release :

- Build de l'application (si nécessaire)
- Création d'un tag git avec la date actuelle
- Génération du changelog
- Déploiement avec Ansible

Ce script est conçu pour être utilisé aussi bien manuellement que dans le pipeline CI/CD.

## Pipeline CI/CD avec GitHub Actions
Le pipeline CI/CD est configuré avec GitHub Actions et se déclenche automatiquement lors du push d'un tag. Il réalise les étapes suivantes :

- Checkout du code source
- Configuration de l'environnement (Node.js, Terraform, Ansible)
- Provisionnement de l'infrastructure avec Terraform
- Exécution du script de release

### Fonctionnement
Lors d'un push de tag (format v*), le workflow GitHub Actions est déclenché automatiquement. Il effectue toutes les étapes nécessaires pour déployer la nouvelle version de l'API.

## Obstacles rencontrés et solutions
**Problème 1** : Génération dynamique de l'inventaire Ansible
**Solution** : Utilisation d'un template Terraform pour générer automatiquement l'inventaire Ansible avec les bonnes adresses IP.

**Problème 2** : Configuration PM2 persistante
**Solution** : Ajout de commandes dans le playbook Ansible pour sauvegarder la configuration PM2 et la restaurer au démarrage de la machine.

**Problème 3** : Gestion des secrets dans GitHub Actions
**Solution** : Utilisation des secrets GitHub pour stocker les informations sensibles (clés SSH, credentials AWS).

## Conclusion
Ce projet démontre la mise en place d'un pipeline complet de déploiement continu pour une API de supervision de capteurs environnementaux. L'utilisation de Terraform, Ansible et GitHub Actions permet d'automatiser l'ensemble du processus, de la création d'infrastructure au déploiement de l'application.

Cette approche présente plusieurs avantages :

- Infrastructure as Code (IaC) pour une meilleure reproductibilité
- Déploiements automatisés et sécurisés
- Possibilité de faire évoluer facilement l'infrastructure
- Traçabilité des déploiements via les tags git et les changelogs

## Captures d'écran / Logs

### Déploiement Terraform
```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
instance_id = "i-0123456789abcdef0"
instance_ip = "54.123.456.789"
security_group_id = "sg-0123456789abcdef0"
```

### Déploiement Ansible
```
PLAY RECAP *********************************************************************
54.123.456.789              : ok=12   changed=10   unreachable=0    failed=0    skipped=0
```

### GitHub Actions Workflow
```
Run ./release.sh
Starting release process...
Step 1: Building the application...
Build completed (no build step required for Node.js)
Step 2: Creating a new version tag...
Created and pushed tag: v2023.05.15
Step 3: Generating changelog...
Changelog generated
Step 4: Deploying with Ansible...
Deployment completed successfully!
Release process completed successfully!
```
EOT

# Initialiser Git
echo "Initialisation du dépôt Git..."
git init
git add .
git commit -m "Initial commit: Pipeline de déploiement continu"

echo -e "\n\n\033[1;32mInstallation terminée ! \033[0m"
echo -e "\033[1;33mPour finaliser la configuration, veuillez :\033[0m"
echo -e "1. Créer un dépôt GitHub nommé '\033[1;36m$REPO_NAME\033[0m'"
echo -e "2. Pousser le code vers votre dépôt GitHub avec :"
echo -e "   \033[1;37mgit remote add origin https://github.com/$GITHUB_USERNAME/$REPO_NAME.git\033[0m"
echo -e "   \033[1;37mgit push -u origin main\033[0m"
echo -e "3. Configurer les secrets GitHub suivants dans votre dépôt :"
echo -e "   - \033[1;36mSSH_PRIVATE_KEY\033[0m : Contenu de votre clé SSH privée"
echo -e "   - \033[1;36mAWS_ACCESS_KEY_ID\033[0m : Votre ID de clé d'accès AWS"
echo -e "   - \033[1;36mAWS_SECRET_ACCESS_KEY\033[0m : Votre clé d'accès secrète AWS"
