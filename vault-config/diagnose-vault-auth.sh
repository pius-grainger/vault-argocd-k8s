#!/bin/bash

# Vault Authentication Diagnostic Script
# Run this to diagnose Vault auth issues

set -e

VAULT_NS="vault"
ESO_NS="external-secrets"
PROD_NS="production"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Vault Authentication Diagnostic Tool${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Function: Check if command succeeds
check_command() {
  local name=$1
  local cmd=$2
  
  if eval "$cmd" &>/dev/null; then
    echo -e "${GREEN}✓${NC} $name"
    return 0
  else
    echo -e "${RED}✗${NC} $name"
    return 1
  fi
}

# 1. Check Vault pods
echo -e "${YELLOW}1. Vault Pod Status${NC}"
echo ""

VAULT_PODS=$(kubectl get pods -n $VAULT_NS --no-headers | grep ^vault- | awk '{print $1}')
for pod in $VAULT_PODS; do
  STATUS=$(kubectl get pod $pod -n $VAULT_NS -o jsonpath='{.status.phase}')
  if [ "$STATUS" == "Running" ]; then
    echo -e "${GREEN}✓${NC} $pod is Running"
  else
    echo -e "${RED}✗${NC} $pod is $STATUS"
  fi
done

echo ""
echo -e "${YELLOW}2. Vault Seal Status${NC}"
echo ""

VAULT_STATUS=$(kubectl exec -n $VAULT_NS vault-0 -- vault status 2>&1 || echo "ERROR")
if echo "$VAULT_STATUS" | grep -q "Sealed"; then
  SEALED=$(echo "$VAULT_STATUS" | grep "Sealed" | awk '{print $NF}')
  INIT=$(echo "$VAULT_STATUS" | grep "Initialized" | awk '{print $NF}')
  
  if [ "$SEALED" == "false" ]; then
    echo -e "${GREEN}✓${NC} Vault is unsealed"
  else
    echo -e "${RED}✗${NC} Vault is SEALED - needs unsealing"
  fi
  
  if [ "$INIT" == "true" ]; then
    echo -e "${GREEN}✓${NC} Vault is initialized"
  else
    echo -e "${RED}✗${NC} Vault is NOT initialized"
  fi
else
  echo -e "${RED}✗${NC} Could not get Vault status"
  echo "   Error: $(echo "$VAULT_STATUS" | head -3)"
fi

echo ""
echo -e "${YELLOW}3. Vault Auth Methods${NC}"
echo ""

# This will likely fail without auth
AUTH_LIST=$(kubectl exec -n $VAULT_NS vault-0 -- vault auth list 2>&1 || echo "FAILED")
if echo "$AUTH_LIST" | grep -q "kubernetes"; then
  echo -e "${GREEN}✓${NC} Kubernetes auth method is enabled"
  
  # Try to read config
  if kubectl exec -n $VAULT_NS vault-0 -- vault read auth/kubernetes/config &>/dev/null; then
    echo -e "${GREEN}✓${NC} Kubernetes auth config is readable"
  else
    echo -e "${RED}✗${NC} Kubernetes auth config is NOT readable (may need authentication)"
  fi
else
  if echo "$AUTH_LIST" | grep -i "permission denied"; then
    echo -e "${YELLOW}⚠${NC} Kubernetes auth status unknown (permission denied - auth required)"
  else
    echo -e "${RED}✗${NC} Kubernetes auth method is NOT enabled"
  fi
fi

echo ""
echo -e "${YELLOW}4. Vault Policies${NC}"
echo ""

POLICY_LIST=$(kubectl exec -n $VAULT_NS vault-0 -- vault policy list 2>&1 || echo "FAILED")
if echo "$POLICY_LIST" | grep -q "external-secrets"; then
  echo -e "${GREEN}✓${NC} external-secrets policy exists"
else
  if echo "$POLICY_LIST" | grep -i "permission denied"; then
    echo -e "${YELLOW}⚠${NC} Policy list unknown (permission denied - auth required)"
  else
    echo -e "${RED}✗${NC} external-secrets policy NOT found"
  fi
fi

echo ""
echo -e "${YELLOW}5. SecretStore Status${NC}"
echo ""

SS_STATUS=$(kubectl get secretstore vault-backend -n $ESO_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "UNKNOWN")
if [ "$SS_STATUS" == "True" ]; then
  echo -e "${GREEN}✓${NC} SecretStore is Ready"
elif [ "$SS_STATUS" == "False" ]; then
  echo -e "${RED}✗${NC} SecretStore is NOT Ready"
  # Show error
  ERROR=$(kubectl get secretstore vault-backend -n $ESO_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  echo "   Error: $ERROR"
else
  echo -e "${YELLOW}⚠${NC} SecretStore status unknown"
fi

CSS_STATUS=$(kubectl get clustersecretstore vault-backend-cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "UNKNOWN")
if [ "$CSS_STATUS" == "True" ]; then
  echo -e "${GREEN}✓${NC} ClusterSecretStore is Ready"
else
  echo -e "${RED}✗${NC} ClusterSecretStore is NOT Ready"
  CSS_ERROR=$(kubectl get clustersecretstore vault-backend-cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  echo "   Error: $CSS_ERROR"
fi

echo ""
echo -e "${YELLOW}6. ExternalSecrets Sync Status${NC}"
echo ""

if kubectl get externalsecret -n $PROD_NS &>/dev/null; then
  EXTSECRETS=$(kubectl get externalsecret -n $PROD_NS -o jsonpath='{.items[*].metadata.name}')
  for secret in $EXTSECRETS; do
    READY=$(kubectl get externalsecret $secret -n $PROD_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    REASON=$(kubectl get externalsecret $secret -n $PROD_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')
    
    if [ "$READY" == "True" ]; then
      echo -e "${GREEN}✓${NC} ExternalSecret $secret: Ready"
    else
      echo -e "${RED}✗${NC} ExternalSecret $secret: $REASON"
    fi
  done
else
  echo -e "${YELLOW}⚠${NC} No ExternalSecrets found"
fi

echo ""
echo -e "${YELLOW}7. Kubernetes Secret Data${NC}"
echo ""

if kubectl get secret app-secrets -n $PROD_NS &>/dev/null 2>&1; then
  DATA_COUNT=$(kubectl get secret app-secrets -n $PROD_NS -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*":' | wc -l)
  if [ "$DATA_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Secret 'app-secrets' has $DATA_COUNT keys"
  else
    echo -e "${RED}✗${NC} Secret 'app-secrets' has NO data"
  fi
else
  echo -e "${YELLOW}⚠${NC} Secret 'app-secrets' not found"
fi

echo ""
echo -e "${YELLOW}8. External Secrets Operator Logs${NC}"
echo ""

LOG_ERROR=$(kubectl logs -n $ESO_NS -l app.kubernetes.io/name=external-secrets --tail=5 2>&1 | grep -i "permission denied" | head -1)
if [ -n "$LOG_ERROR" ]; then
  echo -e "${RED}✗${NC} Found auth error in logs:"
  echo "   $LOG_ERROR"
else
  LATEST_LOG=$(kubectl logs -n $ESO_NS -l app.kubernetes.io/name=external-secrets --tail=1 2>&1)
  if echo "$LATEST_LOG" | grep -q "ready"; then
    echo -e "${GREEN}✓${NC} Recent logs show normal operation"
  else
    echo -e "${YELLOW}⚠${NC} Latest log entry:"
    echo "   $(echo "$LATEST_LOG" | cut -c 1-80)..."
  fi
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}DIAGNOSIS COMPLETE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Recommendation:"
echo ""

if echo "$AUTH_LIST" | grep -i "permission denied"; then
  echo -e "${RED}CRITICAL:${NC} Vault authentication is required to proceed."
  echo ""
  echo "You need to provide the root token from 'vault operator init':"
  echo "  1. Locate your root token (stored offline securely)"
  echo "  2. Run: VAULT_TOKEN=<your_token> VAULT_ADDR=http://vault.vault.svc.cluster.local:8200"
  echo "  3. Re-run setup scripts: bash vault-config/setup-vault-policies.sh"
  echo ""
  echo "See VAULT_RECOVERY.md for detailed recovery instructions."
elif [ "$SS_STATUS" == "False" ]; then
  echo -e "${YELLOW}ACTION REQUIRED:${NC} SecretStore is not ready."
  echo "Check the error message above for details."
elif echo "$EXTSECRETS" | grep -q "False"; then
  echo -e "${YELLOW}ACTION REQUIRED:${NC} Some ExternalSecrets are not syncing."
  echo "Review the logs: kubectl logs -n external-secrets -f"
else
  echo -e "${GREEN}HEALTHY:${NC} All components appear to be functioning."
fi

echo ""
