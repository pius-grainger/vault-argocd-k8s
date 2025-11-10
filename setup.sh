#!/bin/bash

# Complete setup script for ArgoCD + Vault integration
# Run this script to set up the entire GitOps + Secrets infrastructure

set -e

echo "==========================================="
echo "ArgoCD + Vault GitOps Setup"
echo "==========================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_NAMESPACE="vault"
ARGOCD_NAMESPACE="argocd"
ESO_NAMESPACE="external-secrets"
VAULT_ADDR="https://vault.vault.svc.cluster.local:8200"

echo -e "\n${BLUE}Step 1: Create namespaces${NC}"
kubectl apply -f argocd-vault-setup/vault-namespace.yaml
kubectl apply -f argocd-vault-setup/argocd-namespace.yaml
kubectl apply -f argocd-vault-setup/external-secrets-namespace.yaml

echo -e "\n${BLUE}Step 2: Create RBAC for External Secrets${NC}"
kubectl apply -f argocd-vault-setup/external-secrets-rbac.yaml
kubectl apply -f argocd-vault-setup/vault-auth-rbac.yaml

echo -e "\n${BLUE}Step 3: Install Vault (via ArgoCD or Helm)${NC}"
echo "Option A: Using ArgoCD"
echo "  kubectl apply -f argocd-apps/vault-app.yaml"
echo ""
echo "Option B: Using Helm directly"
echo "  helm repo add hashicorp https://helm.releases.hashicorp.com"
echo "  helm install vault hashicorp/vault --namespace vault"

echo -e "\n${BLUE}Step 4: Initialize and Unseal Vault${NC}"
echo "Run the following commands:"
echo "  kubectl exec -it vault-0 -n vault -- vault operator init"
echo "  kubectl exec -it vault-0 -n vault -- vault operator unseal"

echo -e "\n${BLUE}Step 5: Configure Vault Policies${NC}"
echo "Port-forward to Vault and configure:"
echo "  kubectl port-forward -n vault svc/vault 8200:8200"
echo "Then run:"
echo "  export VAULT_ADDR=https://localhost:8200"
echo "  export VAULT_TOKEN=<your-root-token>"
echo "  bash vault-config/setup-vault-policies.sh"
echo "  bash vault-config/setup-k8s-auth.sh"

echo -e "\n${BLUE}Step 6: Install External Secrets Operator${NC}"
echo "  kubectl apply -f argocd-apps/external-secrets-app.yaml"
echo ""
echo "Or using Helm directly:"
echo "  helm repo add external-secrets https://charts.external-secrets.io"
echo "  helm install external-secrets external-secrets/external-secrets \\"
echo "    --namespace external-secrets \\"
echo "    -f helm-values/external-secrets-values.yaml"

echo -e "\n${BLUE}Step 7: Create SecretStore${NC}"
echo "  kubectl apply -f argocd-vault-setup/vault-secretstore.yaml"

echo -e "\n${BLUE}Step 8: Deploy ExternalSecrets${NC}"
echo "  kubectl apply -f examples/production-app-with-secrets.yaml"
echo "  kubectl apply -f examples/staging-secrets.yaml"

echo -e "\n${GREEN}Setup instructions complete!${NC}"
echo -e "\n${BLUE}Next steps:${NC}"
echo "1. Verify all pods are running:"
echo "   kubectl get pods -n vault"
echo "   kubectl get pods -n external-secrets"
echo ""
echo "2. Check ExternalSecret status:"
echo "   kubectl describe externalsecret app-secrets -n production"
echo ""
echo "3. Verify secrets were synced:"
echo "   kubectl get secrets -n production"
