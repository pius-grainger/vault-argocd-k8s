# Vault Authentication Recovery Guide

## Problem

After a Vault pod restart or data loss, the following symptoms appear:

- Vault status shows: `Sealed: false` (unsealed), `Initialized: true`
- External Secrets fails with: **`Error making API request... Code: 403. Errors: * permission denied`**
- Vault logs show auth methods exist but authentication fails
- Unable to read any auth configuration

## Root Cause

This happens when:
1. Vault's Raft storage is lost or corrupted
2. Vault pod restarts and loses in-memory configuration
3. Auth roles and policies were not persisted to storage

## Solution Options

### Option 1: Recover with Root Token (RECOMMENDED)

If you have the root token from the initial `vault operator init`, you can reconfigure everything:

```bash
# 1. Authenticate with root token
export VAULT_ADDR=http://vault.vault.svc.cluster.local:8200
export VAULT_TOKEN=<YOUR_ROOT_TOKEN_FROM_INIT>

# 2. Verify you can access Vault
vault status

# 3. Run the setup scripts
kubectl cp vault-config/setup-vault-policies.sh vault/vault-0:/tmp/ -n vault
kubectl cp vault-config/setup-k8s-auth.sh vault/vault-0:/tmp/ -n vault

# 4. Port-forward and run scripts locally, or exec into pod and run with token
kubectl exec -it -n vault vault-0 -- bash -c '
  VAULT_ADDR=http://127.0.0.1:8200
  VAULT_TOKEN=<YOUR_ROOT_TOKEN>
  export VAULT_ADDR VAULT_TOKEN
  bash /tmp/setup-vault-policies.sh
  bash /tmp/setup-k8s-auth.sh
'
```

### Option 2: Seal and Reinitialize Vault

If root token is lost, reinitialize Vault from scratch:

```bash
# 1. Seal all Vault nodes
kubectl exec -n vault vault-0 -- vault operator seal
kubectl exec -n vault vault-1 -- vault operator seal
kubectl exec -n vault vault-2 -- vault operator seal

# 2. Delete Raft storage (WARNING: Data loss!)
kubectl delete pvc -n vault --all

# 3. Re-unseal Vault
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3

# 4. Unseal all nodes with new keys
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>

# 5. Repeat for vault-1 and vault-2
# ... (raft join commands needed)
```

### Option 3: Manual Vault Bypass (Advanced)

If you have physical/direct access to Vault and no token:

```bash
# Use Shamir keys to unseal and get emergency access
vault operator unseal -migrate <KEY1>
vault operator unseal <KEY2>
vault operator unseal <KEY3>

# If Vault supports it, use recovery keys
vault write sys/raw/core/unseal-keys ...
```

## Prevention

To prevent this in the future:

1. **Store root token securely**
   - AWS Secrets Manager / HashiCorp Vault (nested)
   - Sealed physical safe / HSM
   - Never in Git or ConfigMaps

2. **Enable AWS KMS Auto-Unseal**
   - See `README-unseal.md` for configuration
   - Removes need for manual unseal keys

3. **Persistent Storage**
   - Ensure PVCs are backed by reliable storage (AWS EBS, etc.)
   - Configure PVC retention policies
   - Regular backups

4. **HA Configuration**
   - Current setup: 3-node Raft cluster
   - Verify all nodes can reach each other
   - Monitor storage health

5. **Audit Logging**
   - Enable persistent audit logs
   - Monitor all authentication attempts

## Immediate Actions Needed

**Status: 🔴 CRITICAL - Vault Auth Not Working**

Since you don't have the root token readily available:

1. **Check if token is stored anywhere**
   - AWS Secrets Manager
   - Sealed documentation
   - Team password manager
   - Backup systems

2. **If token found**: Run Option 1 above immediately

3. **If token lost**: Run Option 2 (Seal and Reinitialize)
   - **WARNING:** This deletes all secrets in Vault
   - Only do this if secrets are backed up or not critical yet

## Quick Status Check

```bash
# See current SecretStore status
kubectl describe secretstore vault-backend -n external-secrets

# See External Secret errors
kubectl describe externalsecret app-secrets -n production

# View Vault logs
kubectl logs -n vault vault-0 -f --tail=100
```

## Recovery Checklist

After recovering authentication, verify:

- [ ] `vault status` shows no permission denied errors
- [ ] `vault policy list` shows policies: default, external-secrets, k8s-auth
- [ ] `vault read auth/kubernetes/config` succeeds
- [ ] `vault read auth/kubernetes/role/external-secrets-operator` succeeds
- [ ] `kubectl get secretstore -A` shows `Ready: True`
- [ ] Secrets in production namespace are populated
- [ ] External Secrets pods logs show successful sync

## Next Steps

1. **Secure the root token** - move from temporary storage to secure location
2. **Setup AWS KMS auto-unseal** - prevents future unseal issues
3. **Implement backup/restore** - vault-config/backup-restore.sh
4. **Setup monitoring** - alerts for unsealed status
5. **Run validation** - `bash vault-config/validate-deployment.sh`

---

**Need help?** See TROUBLESHOOTING.md or contact your Vault administrator.
