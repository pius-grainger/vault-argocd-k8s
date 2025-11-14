# Fix Vault Authentication Issue

## Problem
External Secrets Operator cannot authenticate to Vault (403 Permission Denied).

## Root Cause
Vault's Kubernetes auth method is not properly configured or the role/policy is missing.

## Solution

### Step 1: Get Your Vault Root Token

You need the root token from when Vault was initialized. Check:

```bash
# If you saved it locally
cat ~/vault-init.txt

# Or check if it's in a Kubernetes secret
kubectl get secrets -n vault -o yaml | grep -i token
```

If you don't have the root token, you'll need to:
1. Unseal Vault with your unseal keys
2. Use the root token from the original `vault operator init` output

### Step 2: Run the Fix Script

```bash
# Set your root token
export VAULT_TOKEN=<your-root-token>

# Run the fix
bash vault-config/fix-vault-auth.sh
```

### Step 3: Restart External Secrets Operator

```bash
kubectl rollout restart deployment -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Step 4: Verify

```bash
# Check SecretStore status
kubectl get secretstore,clustersecretstore -A

# Check ExternalSecrets
kubectl get externalsecret -n production

# Check if secrets are synced
kubectl get secret app-secrets -n production -o yaml
```

## Alternative: Manual Fix

If you prefer to fix manually:

```bash
# 1. Exec into Vault pod
kubectl exec -it -n vault vault-0 -- sh

# 2. Set token
export VAULT_TOKEN=<your-root-token>

# 3. Enable Kubernetes auth
vault auth enable kubernetes

# 4. Configure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
  disable_iss_validation=true

# 5. Create policy
vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

# 6. Create role
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h
```

## Verification Commands

```bash
# Test Vault auth
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/external-secrets

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Describe ExternalSecret
kubectl describe externalsecret app-secrets -n production
```
