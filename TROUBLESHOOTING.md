# Troubleshooting Guide & Common Issues

## Vault-Related Issues

### Issue 1: Vault Pod Stuck in Initializing

**Symptoms**: Pod status shows `Initializing` for more than 5 minutes

**Diagnosis**:
```bash
kubectl describe pod vault-0 -n vault
kubectl logs vault-0 -n vault
```

**Common Causes**:
- Insufficient storage space
- Network connectivity issues
- TLS certificate problems
- Permission issues on mounted volumes

**Solutions**:
```bash
# Check available storage
kubectl exec -it vault-0 -n vault -- df -h /vault/data

# Verify network connectivity
kubectl exec -it vault-0 -n vault -- nslookup vault.vault.svc.cluster.local

# Check volume permissions
kubectl exec -it vault-0 -n vault -- ls -la /vault/data

# If storage is issue, check PVC
kubectl get pvc -n vault
kubectl describe pvc data-vault-0 -n vault
```

### Issue 2: Vault Won't Unseal

**Symptoms**: Vault status shows `Sealed: true` after unseal attempts

**Diagnosis**:
```bash
kubectl exec -it vault-0 -n vault -- vault status
```

**Common Causes**:
- Using wrong unseal keys
- Pod restarted (loses unseal state)
- Reaching max unseal attempts
- Key threshold not met

**Solutions**:
```bash
# Verify correct format of unseal key
echo "<UNSEAL_KEY>" | wc -c  # Should be reasonable length

# Try unsealing with correct key format
kubectl exec -it vault-0 -n vault -- vault operator unseal

# If all keys used, need to restart
kubectl rollout restart statefulset/vault -n vault

# Check unseal progress
kubectl exec -it vault-0 -n vault -- vault status | grep "Unseal Progress"
```

### Issue 3: TLS Certificate Errors

**Symptoms**: 
```
x509: certificate signed by unknown authority
```

**Diagnosis**:
```bash
# Check certificate
kubectl get secret vault-tls -n vault -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text

# Check certificate expiry
kubectl exec -it vault-0 -n vault -- curl -k https://localhost:8200/v1/sys/health
```

**Solutions**:
```bash
# For development (skip verification):
export VAULT_SKIP_VERIFY=true

# For production (proper certificate):
# 1. Generate valid certificate
# 2. Update secret
kubectl create secret tls vault-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n vault \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart Vault
kubectl rollout restart statefulset/vault -n vault
```

### Issue 4: Kubernetes Auth Not Working

**Symptoms**: 
```
errors:
- permission denied
```

**Diagnosis**:
```bash
# Check if auth method is enabled
vault auth list | grep kubernetes

# Check auth role configuration
vault read auth/kubernetes/role/external-secrets-operator

# Test token review
vault write auth/kubernetes/config -

# Check K8s API connectivity
vault read auth/kubernetes/config
```

**Solutions**:
```bash
# Re-enable and reconfigure
vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  token_reviewer_jwt=$(kubectl -n external-secrets get secret $(kubectl -n external-secrets get secret -o jsonpath='{.items[0].metadata.name}') -o jsonpath='{.data.token}' | base64 -d) \
  kubernetes_host=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Re-create role
vault write auth/kubernetes/role/external-secrets-operator \
  bound_service_account_names=external-secrets-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h
```

## External Secrets Operator Issues

### Issue 5: ExternalSecret Stuck in Pending

**Symptoms**: 
```
Status: Pending
Message: ProviderError | secret not found
```

**Diagnosis**:
```bash
# Describe the ExternalSecret
kubectl describe externalsecret app-secrets -n production

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50 | grep -i error

# Check if secret exists in Vault
vault kv get secret/applications/demo-app
```

**Common Causes**:
- Secret doesn't exist in Vault at specified path
- Vault policy doesn't grant read permission
- Vault is unreachable
- Wrong path format (v1 vs v2)
- Typo in secret key reference

**Solutions**:
```bash
# 1. Verify secret exists in Vault
vault kv list secret/
vault kv get secret/applications/demo-app

# 2. Verify Vault policy allows read
vault policy read external-secrets

# 3. If missing, create it
vault kv put secret/applications/demo-app \
  username="test-user" \
  password="test-password"

# 4. Test Vault connectivity from ESO pod
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health

# 5. Check ExternalSecret format
kubectl get externalsecret app-secrets -n production -o yaml | head -50
```

### Issue 6: High CPU/Memory Usage in ESO

**Symptoms**: ESO pod consuming excessive resources

**Diagnosis**:
```bash
# Check resource usage
kubectl top pod -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check number of ExternalSecrets
kubectl get externalsecrets -A --no-headers | wc -l

# Check refresh intervals
kubectl get externalsecrets -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.refreshInterval}{"\n"}{end}'
```

**Common Causes**:
- Too many ExternalSecrets
- Refresh interval too low (< 1 minute)
- Vault is slow to respond
- Memory leaks in older versions

**Solutions**:
```bash
# 1. Increase refresh interval
kubectl patch externalsecret app-secrets -n production \
  -p '{"spec":{"refreshInterval":"5m"}}' --type merge

# 2. Increase resource limits
kubectl set resources deployment/external-secrets -n external-secrets \
  --limits=cpu=1000m,memory=1Gi \
  --requests=cpu=500m,memory=512Mi

# 3. Upgrade ESO to latest version
helm upgrade external-secrets external-secrets/external-secrets -n external-secrets

# 4. Split ExternalSecrets across multiple instances
# Deploy multiple ESO replicas with pod affinity
```

### Issue 7: Webhook Errors

**Symptoms**: 
```
Error: failed to call webhook "esvalidation.external-secrets.io"
```

**Diagnosis**:
```bash
# Check webhook pod
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets-webhook

# Check webhook service
kubectl get svc -n external-secrets | grep webhook

# Test webhook connectivity
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  curl https://external-secrets-webhook:10250/validate?timeout=5s
```

**Solutions**:
```bash
# Restart webhook
kubectl rollout restart deployment/external-secrets-webhook -n external-secrets

# Check certificate validity
kubectl get secret external-secrets-webhook -n external-secrets -o yaml

# Disable webhook (temporary)
kubectl patch externalsecrets -p '{"webhookClientConfig.insecureSkipVerify":true}' --type merge
```

## Network & Connectivity Issues

### Issue 8: Vault Unreachable from ESO

**Symptoms**:
```
Error: failed to login
Error: Vault is unreachable
```

**Diagnosis**:
```bash
# Test DNS resolution
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  nslookup vault.vault.svc.cluster.local

# Test TCP connectivity
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  nc -zv vault.vault.svc.cluster.local 8200

# Check network policies
kubectl get networkpolicies -n external-secrets
kubectl get networkpolicies -n vault
```

**Solutions**:
```bash
# 1. Check if network policies are blocking traffic
kubectl delete networkpolicy external-secrets-network-policy -n external-secrets

# 2. Verify Vault is accessible
kubectl port-forward -n vault svc/vault 8200:8200
# Try: curl https://localhost:8200/v1/sys/health -k

# 3. Check service DNS
kubectl get svc -n vault vault

# 4. Verify namespace labels for network policies
kubectl get ns -L name

# 5. Re-apply network policies with correct selectors
kubectl apply -f argocd-vault-setup/network-policies.yaml
```

### Issue 9: DNS Resolution Issues

**Symptoms**:
```
Error: server name does not match service account name
Error: could not resolve service name
```

**Solutions**:
```bash
# Check CoreDNS
kubectl get pods -n kube-system | grep coredns

# Test DNS from pod
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  nslookup vault.vault.svc.cluster.local

# If DNS fails, restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Check /etc/resolv.conf in pod
kubectl exec -it deployment/external-secrets -n external-secrets -- \
  cat /etc/resolv.conf
```

## ArgoCD Integration Issues

### Issue 10: ArgoCD Can't Sync Application

**Symptoms**:
```
Application sync failed
Resource creation failed
```

**Diagnosis**:
```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check application status
kubectl describe application vault -n argocd

# Check ArgoCD repo connectivity
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

**Solutions**:
```bash
# 1. Verify repo credentials
kubectl get secrets -n argocd | grep repository

# 2. Check RBAC for application namespace
kubectl get clusterrole argocd-application-controller -o yaml

# 3. Retry sync
kubectl patch application vault -n argocd \
  -p '{"metadata":{"finalizers":null}}' --type merge

# 4. Check resource validation
kubectl apply --dry-run=client -f argocd-apps/vault-app.yaml
```

## Secret Not Being Updated

### Issue 11: Secrets Not Refreshing

**Symptoms**: Secret value in K8s doesn't match Vault value

**Diagnosis**:
```bash
# Check refresh interval
kubectl get externalsecret app-secrets -n production -o jsonpath='{.spec.refreshInterval}'

# Check last sync time
kubectl describe externalsecret app-secrets -n production | grep -i "Last Sync"

# Check Vault value
vault kv get secret/applications/demo-app

# Check K8s secret value
kubectl get secret app-secrets -n production -o jsonpath='{.data.password}' | base64 -d
```

**Solutions**:
```bash
# 1. Reduce refresh interval
kubectl patch externalsecret app-secrets -n production \
  -p '{"spec":{"refreshInterval":"5m"}}' --type merge

# 2. Force refresh by deleting pod
kubectl delete pod -n external-secrets -l app.kubernetes.io/name=external-secrets

# 3. Check if secret changed in Vault
vault kv metadata get secret/applications/demo-app

# 4. Re-apply ExternalSecret
kubectl apply -f examples/production-app-with-secrets.yaml -n production

# 5. Check deletion policy
kubectl get externalsecret app-secrets -n production -o jsonpath='{.spec.target.deletionPolicy}'
```

## Performance Issues

### Issue 12: Slow Secret Sync

**Symptoms**: ExternalSecret takes long time to sync

**Diagnosis**:
```bash
# Check sync duration
kubectl describe externalsecret app-secrets -n production

# Check Vault response time
vault read sys/health -format=table

# Monitor ESO performance
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets | grep -i duration
```

**Solutions**:
```bash
# 1. Check Vault performance
vault status

# 2. Optimize Vault policies (remove unnecessary path patterns)
vault policy list

# 3. Increase refresh interval
kubectl patch externalsecret app-secrets -n production \
  -p '{"spec":{"refreshInterval":"10m"}}' --type merge

# 4. Scale up Vault (if needed)
kubectl scale statefulset vault -n vault --replicas=3

# 5. Monitor and tune Vault resources
kubectl top pods -n vault
```

## Emergency Procedures

### Complete Reset of External Secrets

```bash
# WARNING: This deletes all synced secrets!
# Only use in case of total failure

# 1. Delete ExternalSecrets
kubectl delete externalsecrets -A --all

# 2. Delete synced Secrets
kubectl delete secrets -A -l created-by=external-secrets

# 3. Restart ESO
kubectl rollout restart deployment/external-secrets -n external-secrets

# 4. Re-apply ExternalSecrets
kubectl apply -f examples/production-app-with-secrets.yaml
```

### Vault Emergency Unsealing

```bash
# If normal unseal fails
# 1. Check if pod is still running
kubectl get pods vault-0 -n vault

# 2. Restart pod (will be sealed again)
kubectl delete pod vault-0 -n vault

# 3. Wait for pod to be ready
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=300s

# 4. Unseal again with all 3+ keys
vault operator unseal KEY1
vault operator unseal KEY2
vault operator unseal KEY3
```

## Verification Checklist

When troubleshooting, verify in order:

1. **Kubernetes Health**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

2. **Component Status**
   ```bash
   kubectl get pods -n vault
   kubectl get pods -n external-secrets
   kubectl get pods -n argocd
   ```

3. **Network Connectivity**
   ```bash
   kubectl exec -it deployment/external-secrets -n external-secrets -- \
     curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health
   ```

4. **Vault Status**
   ```bash
   vault status
   vault auth list
   vault policy list
   ```

5. **Secret Existence**
   ```bash
   vault kv get secret/applications/demo-app
   vault kv list secret/
   ```

6. **ExternalSecret Status**
   ```bash
   kubectl describe externalsecret app-secrets -n production
   ```

7. **Secret Presence**
   ```bash
   kubectl get secret app-secrets -n production
   kubectl get secret app-secrets -n production -o yaml
   ```

8. **Log Review**
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
   kubectl logs -n vault -l app.kubernetes.io/name=vault --tail=100
   ```

## Getting Help

If issues persist:

1. Collect diagnostics:
   ```bash
   mkdir diagnostics
   kubectl cluster-info dump --output-directory=diagnostics/
   kubectl get all -n vault -o yaml > diagnostics/vault-all.yaml
   kubectl get all -n external-secrets -o yaml > diagnostics/eso-all.yaml
   kubectl get externalsecrets -A -o yaml > diagnostics/externalsecrets.yaml
   ```

2. Review logs:
   ```bash
   kubectl logs -n vault -l app.kubernetes.io/name=vault > diagnostics/vault.log
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets > diagnostics/eso.log
   ```

3. Check documentation links in SETUP_GUIDE.md

4. Review GitHub issues for similar problems
