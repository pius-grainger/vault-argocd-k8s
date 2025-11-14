# ArgoCD + Vault GitOps Setup

This repository contains configurations and best practices for implementing a secure GitOps workflow using ArgoCD with Vault for secret encryption across Kubernetes namespaces.

## Architecture Overview

```
Git Repository
      ↓
  ArgoCD (GitOps Operator)
      ↓
  ArgoCD ApplicationSets
      ↓
  Helm Charts / Kustomize
      ↓
  Sealed Secrets / Vault-integrated Secrets
      ↓
  Kubernetes Resources (Multiple Namespaces)
      ↓
  External Secrets Operator (reads from Vault)
```

## Key Components

1. **Vault**: Centralized secrets management
2. **ArgoCD**: GitOps operator for declarative deployments
3. **External Secrets Operator (ESO)**: Syncs secrets from Vault to Kubernetes
4. **ArgoCD Applications**: Define applications managed by ArgoCD
5. **Sealed Secrets**: Optional layer for Git-safe secret storage

## Directory Structure

- `argocd-vault-setup/`: ArgoCD installation and configuration
- `vault-config/`: Vault policies, auth methods, and KV secret paths
- `argocd-apps/`: ArgoCD Application manifests
- `helm-values/`: Helm values for External Secrets Operator
- `examples/`: Example applications with secret management

## Quick Start

### 1. Deploy Vault
```bash
kubectl apply -f argocd-vault-setup/vault-namespace.yaml
kubectl apply -f argocd-vault-setup/vault-statefulset.yaml
```

### 2. Initialize and Unseal Vault
```bash
# Automated initialization and unsealing
kubectl apply -f argocd-vault-setup/vault-init-job.yaml

# Verify Vault is unsealed
kubectl exec -n vault vault-0 -- vault status
```

### 3. Configure Vault Authentication
```bash
# Get root token from the secret
export VAULT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d)

# Run the fix script to configure Kubernetes auth
bash vault-config/fix-vault-auth.sh
```

### 4. Deploy External Secrets Operator
```bash
kubectl apply -f argocd-vault-setup/external-secrets-namespace.yaml
kubectl apply -f argocd-vault-setup/external-secrets-serviceaccount.yaml
kubectl apply -f argocd-vault-setup/external-secrets-rbac.yaml

# Install External Secrets Operator (via Helm or manifests)
helm install external-secrets external-secrets/external-secrets -n external-secrets
```

### 5. Create SecretStore
```bash
kubectl apply -f argocd-vault-setup/vault-secretstore.yaml
```

### 6. Test the Setup
```bash
# Run comprehensive test
bash vault-config/test-vault-setup.sh

# Or run diagnostics
bash vault-config/diagnose-vault-auth.sh
```

### 7. Deploy Applications
Use the examples in `examples/` directory to create ExternalSecrets for your applications.

Refer to the detailed setup guides in each directory.
