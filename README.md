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

1. **Install Vault**
2. **Install ArgoCD**
3. **Install External Secrets Operator**
4. **Configure Vault Auth and Policies**
5. **Create SecretStore and ExternalSecret resources**
6. **Deploy applications via ArgoCD**

Refer to the detailed setup guides in each directory.
