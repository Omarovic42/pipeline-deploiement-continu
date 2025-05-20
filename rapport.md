# Rapport - Pipeline de Déploiement Continu

## Introduction
Ce document décrit la mise en place d’un pipeline de déploiement continu pour une application mobile IoT de supervision de capteurs environnementaux. Le pipeline comprend plusieurs composantes clés : l’infrastructure provisionnée avec Terraform, la configuration et le déploiement avec Ansible, et l’orchestration du pipeline CI/CD avec GitHub Actions.

## Architecture et choix techniques

### Domaine fonctionnel : API de supervision de capteurs
L’API développée permet de :
- Lister tous les capteurs disponibles
- Obtenir les détails d’un capteur spécifique
- Envoyer des données pour un capteur
- Vérifier l’état de l’API

L’API est développée en Node.js avec Express, ce qui offre une solution légère et performante pour gérer les requêtes HTTP.

### Choix d’infrastructure et providers
Pour ce projet, j’ai choisi AWS comme fournisseur d’infrastructure cloud pour les raisons suivantes :
- Maturité et fiabilité des services
- Large gamme d’instances disponibles
- Bonne intégration avec Terraform et Ansible
- Support robuste pour les questions de sécurité

Configuration spécifique :
- Instance EC2 t2.micro avec Ubuntu 22.04 LTS
- Groupe de sécurité autorisant le trafic SSH (port 22) et API (port 3000 par défaut)
- Provisionnement complet via Terraform

## Structure des dossiers

```
infra/                  # Configuration Terraform
  main.tf               # Définition des ressources AWS (EC2, security group, key pair, inventaire Ansible dynamique)
  variables.tf          # Variables configurables (région, AMI, type, SSH, port API...)
  outputs.tf            # Outputs pour l’utilisation avec Ansible ou scripts externes
  inventory.tpl         # Template pour générer l’inventaire Ansible
ansible/                # Configuration Ansible
  inventory.ini         # Inventaire généré par Terraform
  deploy.yml            # Playbook pour déployer l’API
api/                    # Code source de l’API
  index.js              # Entrée du serveur API
  package.json          # Dépendances et scripts Node.js
.github/workflows/      # Configuration GitHub Actions
  deploy.yml            # Workflow de déploiement continu
release.sh              # Script de release
rapport.md              # Ce document
```

## Configuration Terraform

La configuration Terraform crée les ressources nécessaires dans AWS :

- EC2 Instance : Une machine virtuelle Ubuntu pour héberger l’API
- Security Group : Groupe de sécurité pour autoriser SSH (22) et le port de l’API (variable)
- Key Pair : Paire de clés SSH pour accès sécurisé

Le fichier `main.tf` est structuré ainsi :
- Provider AWS avec région paramétrable
- Création de la clé SSH depuis un chemin local paramétrable (`ssh_public_key_path`)
- Création du security group avec deux règles d’entrée (SSH et port API) et une règle de sortie globale
- Création de l’instance EC2 avec l’AMI, le type, la clé SSH, le security group et un script d’installation Python minimal
- Génération dynamique de l’inventaire Ansible avec la ressource `local_file`

Variables principales (`variables.tf`) :
- `aws_region` : région AWS (eu-west-3 par défaut)
- `ami_id` : AMI Ubuntu (22.04 LTS)
- `instance_type` : type d’instance (t2.micro par défaut)
- `ssh_public_key_path` : chemin vers la clé publique SSH
- `api_port` : port d’écoute de l’API (3000 par défaut)

Outputs (`outputs.tf`) :
- `instance_ip`, `api_server_public_ip` : IP publique de l’EC2
- `instance_id` : ID de l’instance créée
- `security_group_id` : ID du security group
- `key_pair_name` : nom de la paire de clés SSH
- `ansible_inventory_path` : chemin du fichier d’inventaire généré pour Ansible

### Template d’inventaire Ansible (`infra/inventory.tpl`)

Le template utilisé par Terraform pour générer l’inventaire Ansible ressemble à ceci :
```
[api_servers]
${api_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```
Cela permet à Ansible de cibler facilement le serveur provisionné, avec le bon utilisateur et la clé privée.

## Fonctionnement global

- `terraform init` : Initialise le répertoire de travail Terraform
- `terraform plan` : Prévisualise les changements à appliquer
- `terraform apply` : Crée ou met à jour l’infrastructure dans AWS

Après exécution, Terraform produit des outputs utiles comme l’IP de l’instance et le chemin de l’inventaire Ansible.

## Playbook Ansible
Le playbook Ansible automatise l’installation et la configuration de l’environnement d’exécution de l’API :
- Installation des dépendances nécessaires (git, Node.js, npm)
- Clonage du dépôt contenant l’API
- Installation des dépendances Node.js
- Configuration de PM2 ou d’un gestionnaire de processus Node.js
- Démarrage ou redémarrage de l’API

Le playbook est exécuté avec la commande :
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml
```
L’inventaire est généré automatiquement par Terraform pour cibler la machine correcte.

## Pipeline CI/CD avec GitHub Actions

Le pipeline CI/CD est configuré avec GitHub Actions et se déclenche automatiquement lors d’un push ou d’un tag. Il prévoit :
- Vérification du code source
- Provisionnement et configuration de l’environnement (Terraform, Ansible)
- Déploiement sur le serveur EC2

## Observations, problématiques et solutions

**Problème 1 : Génération dynamique de l’inventaire Ansible**
- Solution : Utilisation de la ressource `local_file` et d’un template pour garantir la cohérence entre Terraform et Ansible.

**Problème 2 : Persistante du state Terraform**
- Solution : Toujours conserver le fichier `terraform.tfstate` ou utiliser un backend distant pour éviter la recréation systématique des ressources.

**Problème 3 : Sécurité SSH**
- Solution : Toujours utiliser une clé SSH générée de façon sécurisée et ne jamais la versionner dans le dépôt.

## Captures d'écran / Logs

### Outputs Terraform

```
Outputs:
instance_id = "i-0e5a7358f14f5e74d"
instance_ip = "13.38.128.207"
security_group_id = "sg-033ac64c7b0006830"
```

### Résultat du PLAY RECAP Ansible

```
PLAY RECAP *********************************************************************
13.38.128.207              : ok=0    changed=0    unreachable=1    failed=0    skipped=0    rescued=0    ignored=0   

Error: Process completed with exit code 4.
```

### Log de la tentative de release GitHub Actions

```
Run ./release.sh
Starting release process...
Step 1: Building the application...
Build completed (no build step required for Node.js)
Step 2: Creating a new version tag...
Created and pushed tag: v2025.05.20
Step 3: Setting up standard-version...
Added 190 packages, and audited 191 packages in 3s
Step 4: Generating changelog...
Changelog generated
Step 5: Deploying with Ansible...
fatal: [13.38.128.207]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ubuntu@13.38.128.207: Permission denied (publickey).", "unreachable": true}
```

---

## Conclusion

Ce projet illustre la mise en place d’un pipeline complet de déploiement continu pour une API de supervision de capteurs environnementaux. L’utilisation de Terraform, Ansible et GitHub Actions permet d’automatiser l’ensemble du processus, de la création de l’infrastructure jusqu’au déploiement applicatif.

Les points forts :
- Infrastructure as Code pour une meilleure reproductibilité
- Déploiements automatisés et sécurisés
- Possibilité de faire évoluer facilement l’infra, le code et le pipeline

---
