# Implementation Checklist & Best Practices

## Pre-Implementation Phase

### Planning
- [ ] Define secret management strategy (centralized vs distributed)
- [ ] Identify all applications that need secrets
- [ ] Document secret types (DB credentials, API keys, certificates, etc.)
- [ ] Plan namespace strategy (prod, staging, dev)
- [ ] Determine Vault deployment model (HA vs standalone)
- [ ] Plan backup and disaster recovery strategy
- [ ] Define secret rotation policies
- [ ] Plan monitoring and alerting strategy

### Infrastructure Requirements
- [ ] Kubernetes cluster 1.16+ ready
- [ ] Sufficient storage for Vault (10GB+ for production)
- [ ] Network connectivity between components
- [ ] DNS resolution working properly
- [ ] TLS certificates available (self-signed for dev, valid for prod)
- [ ] Persistence volumes available (StatefulSets)

## Installation Phase

### Step 1: Prerequisites Setup
- [ ] Clone repository to your machine
- [ ] Update git repo URLs in manifests
- [ ] Generate TLS certificates for Vault
- [ ] Prepare any custom Vault configurations

### Step 2: Create Core Infrastructure
```bash
# Run these in order
kubectl apply -f argocd-vault-setup/argocd-namespace.yaml
kubectl apply -f argocd-vault-setup/vault-namespace.yaml
kubectl apply -f argocd-vault-setup/external-secrets-namespace.yaml
```

- [ ] Verify namespaces created: `kubectl get ns | grep -E "vault|argocd|external-secrets"`

### Step 3: Setup RBAC
```bash
kubectl apply -f argocd-vault-setup/external-secrets-rbac.yaml
kubectl apply -f argocd-vault-setup/vault-auth-rbac.yaml
kubectl apply -f argocd-vault-setup/vault-agent-injector-rbac.yaml
```

- [ ] Verify service accounts: `kubectl get sa -n external-secrets`

### Step 4: Deploy Vault
```bash
# Option A: Using ArgoCD
kubectl apply -f argocd-apps/vault-app.yaml

# Option B: Using Helm directly
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -n vault
```

- [ ] Verify Vault pods are running: `kubectl get pods -n vault`
- [ ] Wait for all pods to be ready (may take 2-3 minutes)

### Step 5: Initialize Vault
```bash
# Get into a Vault pod
kubectl exec -it vault-0 -n vault -- sh

# Inside the pod
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /tmp/init_output.json

# Save the keys and root token securely!
cat /tmp/init_output.json
```

- [ ] Store root token securely (encrypted, offline)
- [ ] Store unseal keys securely (minimum 3 of 5)
- [ ] Note: Each unseal key is unique and necessary

### Step 6: Unseal Vault
```bash
# Unseal with 3 different keys
for i in 1 2 3; do
  kubectl exec -it vault-0 -n vault -- vault operator unseal <UNSEAL_KEY_$i>
done

# Verify unsealed
kubectl exec -it vault-0 -n vault -- vault status
```

- [ ] Verify Vault status shows "Sealed: false"
- [ ] Check cluster is initialized and unsealed

### Step 7: Configure Vault Policies
```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &

# In another terminal
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=<ROOT_TOKEN>

# Setup policies
bash vault-config/setup-vault-policies.sh

# Setup Kubernetes auth
bash vault-config/setup-k8s-auth.sh
```

- [ ] Verify policies created: `vault policy list`
- [ ] Verify auth methods: `vault auth list`
- [ ] Test K8s auth: `vault write -field=token auth/kubernetes/login ...`

### Step 8: Deploy External Secrets Operator
```bash
# Using ArgoCD
kubectl apply -f argocd-apps/external-secrets-app.yaml

# Or using Helm
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  -f helm-values/external-secrets-values.yaml
```

- [ ] Verify ESO pods are running: `kubectl get pods -n external-secrets`
- [ ] Check ESO logs for errors: `kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets`

### Step 9: Create SecretStore
```bash
kubectl apply -f argocd-vault-setup/vault-secretstore.yaml
```

- [ ] Verify SecretStore created: `kubectl get secretstore -n external-secrets`
- [ ] Verify ClusterSecretStore created: `kubectl get clustersecretstore`

### Step 10: Test with Sample Secrets
```bash
# Create a test namespace
kubectl create namespace test

# Deploy example secret
kubectl apply -f examples/staging-secrets.yaml -n test

# Check if secret was created
kubectl get secrets -n test
kubectl describe externalsecret app-secrets -n test

# Verify secret content
kubectl get secret app-secrets -n test -o jsonpath='{.data.username}' | base64 -d
```

- [ ] ExternalSecret status should be "Ready"
- [ ] Secret should be present in namespace
- [ ] Secret values should match Vault

## Post-Installation Phase

### Security Hardening
- [ ] Apply network policies: `kubectl apply -f argocd-vault-setup/network-policies.yaml`
- [ ] Apply pod security policies: `kubectl apply -f argocd-vault-setup/pod-security-policy.yaml`
- [ ] Configure TLS for all communications
- [ ] Enable audit logging in Vault
- [ ] Set up RBAC for access control

### Production Readiness
- [ ] Enable high availability for Vault (3+ replicas with Raft)
- [ ] Configure automated backups: `bash vault-config/backup-restore.sh full`
- [ ] Set up monitoring: `kubectl apply -f argocd-vault-setup/monitoring.yaml`
- [ ] Configure alerting for critical events
- [ ] Test disaster recovery procedures
- [ ] Document emergency procedures

### Application Integration
- [ ] Update application configurations to use ExternalSecrets
- [ ] Deploy applications with secret references
- [ ] Test application secret access
- [ ] Verify secret rotation works
- [ ] Monitor for errors in logs

## Ongoing Operations

### Daily Checks
```bash
# Verify all components are healthy
kubectl get pods -n vault
kubectl get pods -n external-secrets
kubectl get pods -n argocd

# Check for ExternalSecret issues
kubectl get externalsecrets -A

# Review recent logs
kubectl logs -n vault -l app.kubernetes.io/name=vault --tail=50
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50
```

- [ ] All pods should be Running
- [ ] All ExternalSecrets should be Ready
- [ ] No errors in recent logs

### Weekly Tasks
- [ ] Review access logs: `kubectl logs -n vault -p` (previous pod logs)
- [ ] Check Vault storage usage
- [ ] Verify backups completed successfully
- [ ] Monitor secret refresh rates
- [ ] Review and rotate any exposed credentials

### Monthly Tasks
- [ ] Test disaster recovery procedures
- [ ] Review and update Vault policies
- [ ] Audit all secret access patterns
- [ ] Update and patch components
- [ ] Review security configurations
- [ ] Test backup restoration

## Scaling Considerations

### For High Secret Volume
- Increase ExternalSecrets replicas
- Implement caching strategies
- Use longer refresh intervals where appropriate
- Monitor ESO performance metrics

### For Multiple Teams/Namespaces
- Create separate policies per team
- Use namespace-scoped SecretStores
- Implement RBAC for namespace isolation
- Document secret path conventions

### For Multi-Cluster
- Deploy Vault with replication enabled
- Configure per-cluster Kubernetes auth roles
- Use ApplicationSet for multi-cluster deployment
- Implement failover strategies

## Troubleshooting Reference

### Quick Diagnostic Commands
```bash
# Complete health check
kubectl get ns && kubectl get crd | grep external-secrets && \
kubectl get pods -n vault && kubectl get pods -n external-secrets && \
kubectl get secretstore -A && kubectl get clustersecretstore

# Check ExternalSecret status
kubectl get externalsecrets -A -o wide

# Describe failing resources
kubectl describe externalsecret <name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f --tail=100
kubectl logs -n vault -l app.kubernetes.io/name=vault -f --tail=100
```

### Common Fixes
1. **Vault unreachable**: Check network policies and TLS configuration
2. **Auth failures**: Verify Kubernetes auth role and policies
3. **Secrets not updating**: Check refresh interval and ExternalSecret status
4. **Pod crashes**: Check logs for configuration issues

## Documentation & Knowledge Transfer

- [ ] Document Vault initialization and unsealing procedure
- [ ] Create runbook for emergency situations
- [ ] Document secret naming conventions
- [ ] Create training materials for team
- [ ] Document custom policies and configurations
- [ ] Maintain inventory of all secrets in Vault
- [ ] Document backup and recovery procedures

## Sign-Off

- [ ] All tests passing
- [ ] Team trained on operations
- [ ] Documentation complete
- [ ] Monitoring and alerting configured
- [ ] Disaster recovery tested
- [ ] Go-live approved

**Date**: ___________
**Approved By**: ___________
**Reviewed By**: ___________
