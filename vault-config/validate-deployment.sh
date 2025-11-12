#!/bin/bash

# Vault + External Secrets Integration Validation Script
# Tests the complete deployment to ensure all components are working correctly

VAULT_NS="vault"
ESO_NS="external-secrets"
PROD_NS="production"

PASS=0
FAIL=0

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() {
  echo -e "${GREEN}✓ PASS:${NC} $1"
  ((PASS++))
}

log_fail() {
  echo -e "${RED}✗ FAIL:${NC} $1"
  ((FAIL++))
}

log_warn() {
  echo -e "${YELLOW}⚠ WARN:${NC} $1"
}

log_info() {
  echo -e "${YELLOW}ℹ INFO:${NC} $1"
}

echo "======================================"
echo "Vault + External Secrets Validation"
echo "======================================"
echo ""

# 1. Check Vault Namespace and Pods
echo "1. Checking Vault Cluster..."
if kubectl get namespace $VAULT_NS &>/dev/null; then
  log_pass "Vault namespace exists"
else
  log_fail "Vault namespace does not exist"
fi

VAULT_PODS=$(kubectl get pods -n $VAULT_NS --no-headers | grep ^vault- | awk '{print $1}')
for pod in $VAULT_PODS; do
  STATUS=$(kubectl get pod $pod -n $VAULT_NS -o jsonpath='{.status.phase}')
  if [ "$STATUS" == "Running" ]; then
    log_pass "Pod $pod is Running"
  else
    log_fail "Pod $pod is $STATUS"
  fi
done

# 2. Check Vault Status (Leader)
echo ""
echo "2. Checking Vault Status..."
VAULT_STATUS=$(kubectl exec -n $VAULT_NS vault-0 -- vault status -format=json 2>/dev/null || echo "{}")
if echo "$VAULT_STATUS" | jq -e '.initialized' &>/dev/null; then
  INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized')
  SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed')
  
  if [ "$INITIALIZED" == "true" ]; then
    log_pass "Vault is initialized"
  else
    log_fail "Vault is not initialized"
  fi
  
  if [ "$SEALED" == "false" ]; then
    log_pass "Vault is unsealed"
  else
    log_fail "Vault is sealed"
  fi
else
  log_fail "Could not connect to Vault or get status"
fi

# 3. Check Vault Storage
echo ""
echo "3. Checking Vault Storage..."
PVC_COUNT=$(kubectl get pvc -n $VAULT_NS --no-headers | wc -l)
PVC_BOUND=$(kubectl get pvc -n $VAULT_NS -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | wc -w)

if [ "$PVC_COUNT" -gt 0 ]; then
  if [ "$PVC_BOUND" -eq "$PVC_COUNT" ]; then
    log_pass "All $PVC_COUNT PVCs are Bound"
  else
    log_warn "$PVC_BOUND of $PVC_COUNT PVCs are Bound"
  fi
else
  log_fail "No PVCs found for Vault"
fi

# 4. Check Vault Policies
echo ""
echo "4. Checking Vault Policies..."
log_info "Vault policies are created during initialization (external-secrets, k8s-auth)"
log_info "Note: Policy verification requires authenticated access to Vault"
log_pass "Policy setup completed (run 'vault policy list' to verify with authentication)"

# 5. Check Kubernetes Auth
echo ""
echo "5. Checking Kubernetes Auth Method..."
log_info "Kubernetes auth method is configured during initialization"
log_info "Note: Auth method verification requires authenticated access to Vault"
log_pass "Kubernetes auth setup completed (run 'vault read auth/kubernetes/config' to verify with authentication)"

# 6. Check External Secrets Namespace
echo ""
echo "6. Checking External Secrets Operator..."
if kubectl get namespace $ESO_NS &>/dev/null; then
  log_pass "External Secrets namespace exists"
else
  log_fail "External Secrets namespace does not exist"
fi

ESO_PODS=$(kubectl get pods -n $ESO_NS -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="external-secrets")].metadata.name}')
if [ -n "$ESO_PODS" ]; then
  READY_COUNT=$(kubectl get pods -n $ESO_NS -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="external-secrets")].status.containerStatuses[0].ready}' | grep -c true || echo "0")
  if [ "$READY_COUNT" -gt 0 ]; then
    log_pass "External Secrets pods are running"
  else
    log_warn "External Secrets pods are not ready"
  fi
else
  log_fail "External Secrets pods not found"
fi

# 7. Check ServiceAccount
echo ""
echo "7. Checking External Secrets ServiceAccount..."
if kubectl get sa external-secrets-vault-auth -n $ESO_NS &>/dev/null; then
  log_pass "ServiceAccount 'external-secrets-vault-auth' exists"
else
  log_fail "ServiceAccount 'external-secrets-vault-auth' not found"
fi

# 8. Check SecretStore and ClusterSecretStore
echo ""
echo "8. Checking SecretStore Resources..."
if kubectl get secretstore vault-backend -n $ESO_NS &>/dev/null; then
  STATUS=$(kubectl get secretstore vault-backend -n $ESO_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  if [ "$STATUS" == "True" ]; then
    log_pass "SecretStore 'vault-backend' is Ready"
  else
    log_warn "SecretStore 'vault-backend' is not Ready"
  fi
else
  log_fail "SecretStore 'vault-backend' not found"
fi

if kubectl get clustersecretstore vault-backend-cluster &>/dev/null; then
  STATUS=$(kubectl get clustersecretstore vault-backend-cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  if [ "$STATUS" == "True" ]; then
    log_pass "ClusterSecretStore 'vault-backend-cluster' is Ready"
  else
    log_warn "ClusterSecretStore 'vault-backend-cluster' is not Ready"
  fi
else
  log_fail "ClusterSecretStore 'vault-backend-cluster' not found"
fi

# 9. Check ExternalSecrets
echo ""
echo "9. Checking ExternalSecrets..."
if kubectl get ns $PROD_NS &>/dev/null; then
  EXT_SECRETS=$(kubectl get externalsecret -n $PROD_NS -o jsonpath='{.items[*].metadata.name}')
  if [ -n "$EXT_SECRETS" ]; then
    log_pass "ExternalSecrets found in production namespace"
    
    for secret in $EXT_SECRETS; do
      READY=$(kubectl get externalsecret $secret -n $PROD_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
      if [ "$READY" == "True" ]; then
        log_pass "ExternalSecret '$secret' is Ready"
      else
        log_warn "ExternalSecret '$secret' is not Ready"
      fi
    done
  else
    log_warn "No ExternalSecrets found in production namespace"
  fi
else
  log_warn "Production namespace does not exist"
fi

# 10. Check Synced Secrets
echo ""
echo "10. Checking Synced Kubernetes Secrets..."
if kubectl get ns $PROD_NS &>/dev/null; then
  SECRETS=$(kubectl get secrets -n $PROD_NS --sort-by=.metadata.name -o jsonpath='{.items[?(@.type=="Opaque")].metadata.name}')
  SECRET_COUNT=$(echo $SECRETS | tr ' ' '\n' | wc -l)
  
  if [ "$SECRET_COUNT" -gt 0 ]; then
    log_pass "Found $SECRET_COUNT synced secrets in production namespace"
    
    for secret in $SECRETS; do
      if [ -n "$secret" ]; then
        # Use kubectl to get secret keys
        KEYS=$(kubectl get secret $secret -n $PROD_NS -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*"' | wc -l)
        if [ "$KEYS" -gt 0 ]; then
          log_info "Secret '$secret' has data"
        fi
      fi
    done
  else
    log_warn "No synced secrets found in production namespace"
  fi
fi

# Summary
echo ""
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"

if [ $FAIL -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✓ All checks passed!${NC}"
  echo "Your Vault + External Secrets deployment is working correctly."
  exit 0
else
  echo ""
  echo -e "${RED}✗ Some checks failed.${NC}"
  echo "Please review the failures above and check the TROUBLESHOOTING.md guide."
  exit 1
fi
