# Quick Reference Guide

## Installation Checklist

- [ ] Create namespaces
- [ ] Create RBAC resources
- [ ] Install Vault
- [ ] Initialize and unseal Vault
- [ ] Configure Vault policies
- [ ] Enable Kubernetes auth
- [ ] Install External Secrets Operator
- [ ] Create SecretStore/ClusterSecretStore
- [ ] Deploy ExternalSecrets to namespaces
- [ ] Verify secret syncing

## Common Commands

### Vault Operations

```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Initialize Vault
kubectl exec -it vault-0 -n vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3

# Unseal Vault
kubectl exec -it vault-0 -n vault -- vault operator unseal <KEY>

# Check Vault status
kubectl exec -it vault-0 -n vault -- vault status

# Create a secret
vault kv put secret/databases/postgres \
  host="postgres.default.svc.cluster.local" \
  username="admin" \
  password="secure-password"

# Read a secret
vault kv get secret/databases/postgres

# List secrets
vault kv list secret/databases/

# Write policy
vault policy write external-secrets - <<EOF
path "secret/data/applications/*" {
  capabilities = ["read", "list"]
}
EOF

# Read policy
vault policy read external-secrets
```

### External Secrets Operations

```bash
# List ExternalSecrets
kubectl get externalsecrets -n production

# Describe ExternalSecret
kubectl describe externalsecret app-secrets -n production

# Watch ExternalSecret status
kubectl get externalsecret app-secrets -n production -w

# Check synced secret
kubectl get secret app-secrets -n production
kubectl describe secret app-secrets -n production

# View secret content
kubectl get secret app-secrets -n production -o jsonpath='{.data.password}' | base64 -d

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Check ESO webhook
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets-webhook -f
```

### ArgoCD Operations

```bash
# Get ArgoCD applications
kubectl get applications -n argocd

# Describe ArgoCD application
kubectl describe application vault -n argocd

# Sync application
kubectl patch application vault -n argocd -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f

# Port-forward to ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### Kubernetes Auth Configuration

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
  kubernetes_host=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create auth role
vault write auth/kubernetes/role/external-secrets-operator \
  bound_service_account_names=external-secrets-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h

# Test Kubernetes auth
vault write -field=token auth/kubernetes/login \
  role=external-secrets-operator \
  jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

## File Structure

```
vault/
├── README.md                          # Project overview
├── ARCHITECTURE.md                    # Architecture guide
├── SETUP_GUIDE.md                     # Detailed setup instructions
├── setup.sh                           # Automated setup script
│
├── argocd-vault-setup/               # ArgoCD integration configs
│   ├── argocd-namespace.yaml
│   ├── vault-namespace.yaml
│   ├── external-secrets-namespace.yaml
│   ├── external-secrets-rbac.yaml
│   ├── vault-auth-rbac.yaml
│   ├── vault-agent-injector-rbac.yaml
│   └── vault-secretstore.yaml
│
├── vault-config/                      # Vault configuration
│   ├── vault-configmap.yaml
│   ├── setup-vault-policies.sh
│   └── setup-k8s-auth.sh
│
├── argocd-apps/                       # ArgoCD Application definitions
│   ├── vault-app.yaml
│   ├── external-secrets-app.yaml
│   ├── vault-agent-injector-app.yaml
│   └── external-secrets-applicationset.yaml
│
├── helm-values/                       # Helm values files
│   └── external-secrets-values.yaml
│
└── examples/                          # Example implementations
    ├── production-app-with-secrets.yaml
    ├── staging-secrets.yaml
    └── agent-injector-example.yaml
```

## Configuration Customization

### Change Vault address in SecretStore

```yaml
spec:
  provider:
    vault:
      server: "https://your-vault-server.com:8200"
```

### Change refresh interval for secrets

```yaml
spec:
  refreshInterval: 30m  # Default is 1h
```

### Add new secret path

```yaml
data:
- secretKey: api-token
  remoteRef:
    key: applications/myapp/api-token
    property: token
```

### Change secret creation policy

```yaml
target:
  creationPolicy: Owner  # Owner or None
  deletionPolicy: Delete # Delete or Retain
```

## Environment-Specific Setup

### For Production

1. **High Availability**: 
   - Use Raft storage
   - Deploy 3+ Vault nodes
   - Configure auto-unsealing

2. **Security**:
   - Enable TLS certificates
   - Configure audit logging
   - Implement network policies
   - Use sealed secrets for Git storage

3. **Monitoring**:
   - Enable Prometheus metrics
   - Set up Vault audit logging
   - Monitor ESO sync status

### For Staging

1. Standard setup with single Vault instance
2. File storage acceptable
3. Same security practices as prod (scaled down)

### For Development

1. Single Vault instance (OK to unseal manually)
2. File storage
3. Relaxed security for testing
4. Local Kubernetes cluster (kind, minikube)

## Troubleshooting Checklist

```bash
# 1. Verify all namespaces exist
kubectl get ns | grep -E "vault|external-secrets|argocd"

# 2. Verify all pods are running
kubectl get pods -n vault
kubectl get pods -n external-secrets
kubectl get pods -n argocd

# 3. Check Vault is initialized and unsealed
kubectl exec -it vault-0 -n vault -- vault status

# 4. Verify Kubernetes auth is configured
vault read auth/kubernetes/role/external-secrets-operator

# 5. Check ExternalSecret status
kubectl describe externalsecret app-secrets -n production

# 6. View ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# 7. Verify secret was created in namespace
kubectl get secret app-secrets -n production

# 8. Test reading the secret
kubectl get secret app-secrets -n production -o jsonpath='{.data}' | jq '.' | base64 -d
```

## Next Steps

1. **Implement Git-safe secrets**: Use Sealed Secrets or Vault template
2. **Set up monitoring**: Configure Prometheus + Grafana
3. **Implement backups**: Regular Vault snapshots
4. **Configure rotation**: Set up secret rotation policies
5. **Multi-cluster**: Extend to multiple Kubernetes clusters
6. **SSO Integration**: Integrate with LDAP/OIDC for Vault access
