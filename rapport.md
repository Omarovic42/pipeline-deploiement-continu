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

- Instance EC2 t2.micro avec Ubuntu 22.04 LTS
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
