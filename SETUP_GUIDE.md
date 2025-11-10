# Setup and Troubleshooting Guide

## Prerequisites

1. **Kubernetes Cluster**: 1.16+ (preferably 1.20+)
2. **kubectl**: Latest version
3. **Helm**: 3.0+
4. **ArgoCD**: 2.0+
5. Git repository for GitOps manifests

## Installation Steps

### 1. Create Namespaces

```bash
kubectl apply -f argocd-vault-setup/vault-namespace.yaml
kubectl apply -f argocd-vault-setup/argocd-namespace.yaml
kubectl apply -f argocd-vault-setup/external-secrets-namespace.yaml
```

### 2. Setup RBAC

```bash
kubectl apply -f argocd-vault-setup/external-secrets-rbac.yaml
kubectl apply -f argocd-vault-setup/vault-auth-rbac.yaml
```

### 3. Install Vault

**Using Helm:**
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --values helm-values/vault-values.yaml
```

**Using ArgoCD:**
```bash
kubectl apply -f argocd-apps/vault-app.yaml
```

### 4. Initialize and Unseal Vault

```bash
# Initialize Vault
kubectl exec -it vault-0 -n vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3

# Unseal Vault (repeat 3 times with different unseal keys)
kubectl exec -it vault-0 -n vault -- vault operator unseal <UNSEAL_KEY>

# Verify Vault is unsealed
kubectl exec -it vault-0 -n vault -- vault status
```

### 5. Configure Vault

Port-forward to Vault:
```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

In another terminal:
```bash
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=<ROOT_TOKEN>

# Create policies
bash vault-config/setup-vault-policies.sh

# Configure Kubernetes auth
bash vault-config/setup-k8s-auth.sh
```

### 6. Install External Secrets Operator

**Using Helm:**
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  -f helm-values/external-secrets-values.yaml
```

**Using ArgoCD:**
```bash
kubectl apply -f argocd-apps/external-secrets-app.yaml
```

### 7. Create SecretStore

```bash
kubectl apply -f argocd-vault-setup/vault-secretstore.yaml
```

### 8. Deploy Example Applications

```bash
# Create production namespace
kubectl create namespace production

# Deploy ExternalSecrets and application
kubectl apply -f examples/production-app-with-secrets.yaml
```

## Troubleshooting

### Issue: ExternalSecret stuck in "Pending"

**Check logs:**
```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

**Check ExternalSecret status:**
```bash
kubectl describe externalsecret app-secrets -n production
```

**Common causes:**
- Vault is not accessible
- Service account doesn't have proper permissions
- Kubernetes auth role not configured correctly

### Issue: Vault unseals don't persist

**Solution:** Configure persistent storage or integrated storage (Raft):
```yaml
storage "raft" {
  path = "/vault/data"
}
```

### Issue: "permission denied" errors

**Check Vault policies:**
```bash
vault policy read external-secrets
```

**Check Kubernetes auth binding:**
```bash
vault read auth/kubernetes/role/external-secrets-operator
```

### Issue: TLS certificate errors

**Disable TLS verification (development only):**
```bash
kubectl set env deployment/external-secrets ESO_VAULT_TLS_SKIP=true -n external-secrets
```

**Or provide custom CA bundle in SecretStore:**
```yaml
caBundle: <base64-encoded-cert>
```

## Verification

### Check all pods are running:
```bash
kubectl get pods -n vault
kubectl get pods -n external-secrets
kubectl get pods -n argocd
```

### Verify secrets are synced:
```bash
kubectl get secrets -n production
kubectl get externalsecrets -n production
```

### Check secret content:
```bash
kubectl get secret app-secrets -n production -o jsonpath='{.data.username}' | base64 -d
```

## Security Best Practices

1. **Enable TLS**: Use proper certificates for Vault and cluster communication
2. **RBAC**: Follow least privilege principle in Vault policies
3. **Audit Logging**: Enable Vault audit logs
4. **Backup**: Regularly backup Vault state (if using file storage)
5. **Rotation**: Implement secret rotation policies
6. **GitOps**: Don't commit actual secrets; use encrypted storage or reference patterns
7. **Namespace Isolation**: Use separate policies for each namespace
8. **Service Account**: Use dedicated service accounts for each application

## Advanced Configuration

### Use different Vault instances per environment

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-prod
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault-prod.vault.svc.cluster.local:8200"
      # ... rest of config
```

### Sync secrets to multiple namespaces

Use ApplicationSet or create individual ExternalSecrets in each namespace:
```bash
for ns in production staging development; do
  kubectl create namespace $ns
  kubectl apply -f examples/staging-secrets.yaml -n $ns
done
```

### Rotate secrets automatically

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotated-secret
spec:
  refreshInterval: 15m  # Refresh every 15 minutes
  # ... rest of config
```

## Backup and Disaster Recovery

### Regular Backups

Run backups regularly using the backup script:

```bash
# Full backup
bash vault-config/backup-restore.sh full

# List available backups
bash vault-config/backup-restore.sh list

# Restore from backup
bash vault-config/backup-restore.sh restore <backup_path>
```

### Backup Locations

- Vault state: `/backups/<timestamp>/vault-raft.snap`
- Policies: `/backups/<timestamp>/vault-policy-*.hcl`
- ArgoCD apps: `/backups/<timestamp>/argocd-applications.yaml`
- ExternalSecrets: `/backups/<timestamp>/external-secrets.yaml`

## Advanced Configurations

### Enable Vault Agent Injector

For automatic secret injection into pods without ExternalSecrets:

```bash
kubectl apply -f argocd-apps/vault-agent-injector-app.yaml
```

Use annotations on your pods:
```yaml
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "application"
vault.hashicorp.com/agent-inject-secret-db: "secret/databases/postgres"
```

### Enable Sealed Secrets (Optional - Git-Safe)

For additional encryption layer when storing secrets in Git:

```bash
kubectl apply -f argocd-apps/sealed-secrets-app.yaml
```

Use helper script:
```bash
bash vault-config/sealed-secrets-helper.sh
```

### Multi-Cluster Setup

Deploy secrets across multiple Kubernetes clusters:

```bash
kubectl apply -f examples/multi-cluster-secrets.yaml
```

Configure different Vault servers per cluster in `SecretStore`:
```yaml
vault:
  server: "https://vault-cluster1.example.com:8200"  # Cluster 1
  server: "https://vault-cluster2.example.com:8200"  # Cluster 2
```

### Advanced Vault Configuration

Setup additional features like database secrets, SSH, transit engine:

```bash
export VAULT_ADDR=https://localhost:8200
export VAULT_TOKEN=<your-token>
bash vault-config/setup-advanced-vault.sh
```

### Enable Monitoring

Deploy Prometheus monitoring for Vault and ExternalSecrets:

```bash
kubectl apply -f argocd-vault-setup/monitoring.yaml
```

Monitor key metrics:
- `vault_core_unsealed` - Vault seal status
- `vault_core_handle_login_request_duration_total` - Authentication latency
- `externalsecrets_status_condition` - ExternalSecret sync status

## Security Hardening

### 1. Network Policies

Applied automatically:
```bash
kubectl apply -f argocd-vault-setup/network-policies.yaml
```

### 2. Pod Security Policies

For additional pod security:
```bash
kubectl apply -f argocd-vault-setup/pod-security-policy.yaml
```

### 3. TLS Configuration

Enable TLS for Vault:
1. Generate certificates (self-signed for dev, valid certs for prod)
2. Create TLS secret in vault namespace
3. Configure in vault-secretstore.yaml

### 4. RBAC Best Practices

- Use separate service accounts per application
- Apply principle of least privilege in Vault policies
- Audit all secret access

## Troubleshooting Commands

```bash
# Check Vault logs
kubectl logs -n vault -l app.kubernetes.io/name=vault -f

# Check External Secrets logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Check ExternalSecret status
kubectl get externalsecrets -n production -o wide

# Describe failing ExternalSecret
kubectl describe externalsecret <name> -n production

# Get secret content (base64 encoded)
kubectl get secret <name> -n production -o json | jq '.data'

# Decode a specific secret value
kubectl get secret <name> -n production -o jsonpath='{.data.key}' | base64 -d

# Check Vault Kubernetes auth configuration
vault read auth/kubernetes/role/external-secrets-operator

# Test Kubernetes auth login
vault write -field=token auth/kubernetes/login \
  role=external-secrets-operator \
  jwt=<jwt-token>
```

## Common Issues and Solutions

| Problem | Cause | Solution |
|---------|-------|----------|
| ExternalSecret stuck in Pending | Vault unreachable | Check network connectivity, TLS certificates |
| Permission denied errors | Vault policy too restrictive | Review and expand Vault policy |
| Secrets not updating | Refresh interval too long | Reduce `refreshInterval` in ExternalSecret |
| Pod can't access secret | RBAC misconfiguration | Verify service account permissions |
| Vault won't unseal | Missing unseal keys | Use backed-up unseal keys |
| High CPU usage in ESO | Refresh interval too low | Increase refresh interval (min 1m recommended) |

## Reference Links

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Vault Kubernetes Auth Method](https://www.vaultproject.io/docs/auth/kubernetes)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Kubernetes Service Account Tokens](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Pod Security Policies](https://kubernetes.io/docs/concepts/security/pod-security-policy/)
