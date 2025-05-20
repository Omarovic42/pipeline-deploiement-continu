#!/usr/bin/env bash
set -e
set -x  # Affiche chaque commande exécutée pour le debug

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

# Config git pour GitHub Actions (nécessaire en CI/CD)
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"

# S'assurer que l'on est bien sur la bonne branche (et pas en detached HEAD)
if [ -n "${GITHUB_REF_NAME}" ]; then
  git checkout "${GITHUB_REF_NAME}" || git checkout main
else
  git checkout main
fi

# Créer le tag du jour si non existant
VERSION="v$(date +'%Y.%m.%d')"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo -e "${YELLOW}Tag $VERSION already exists, skipping tag creation.${NC}"
else
  git tag $VERSION
  git push --tags
  echo -e "${GREEN}Created and pushed tag: $VERSION${NC}"
fi

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
