#!/bin/bash
set -e

VAULT_NS="vault"
ESO_NS="external-secrets"

echo "=== Fixing Vault Authentication ==="
echo ""

# Check if root token is provided
if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: VAULT_TOKEN environment variable is not set"
  echo ""
  echo "Please set your Vault root token:"
  echo "  export VAULT_TOKEN=<your-root-token>"
  echo ""
  echo "If you don't have the root token, check your init output or unseal keys."
  exit 1
fi

echo "✓ Vault token found"
echo ""

# Enable Kubernetes auth if not already enabled
echo "1. Enabling Kubernetes auth method..."
kubectl exec -n $VAULT_NS vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault auth enable kubernetes 2>/dev/null || echo 'Already enabled'
"

# Get Kubernetes CA and token
echo "2. Retrieving Kubernetes credentials..."
K8S_HOST="https://kubernetes.default.svc.cluster.local:443"
SA_SECRET=$(kubectl get sa -n $ESO_NS external-secrets-vault-auth -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")

if [ -z "$SA_SECRET" ]; then
  echo "   Creating service account token..."
  kubectl create token external-secrets-vault-auth -n $ESO_NS --duration=87600h > /tmp/sa-token
  SA_JWT=$(cat /tmp/sa-token)
else
  SA_JWT=$(kubectl get secret -n $ESO_NS $SA_SECRET -o jsonpath='{.data.token}' | base64 -d)
fi

K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Configure Kubernetes auth
echo "3. Configuring Kubernetes auth..."
kubectl exec -n $VAULT_NS vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault write auth/kubernetes/config \
    token_reviewer_jwt=\"$SA_JWT\" \
    kubernetes_host=\"$K8S_HOST\" \
    kubernetes_ca_cert=\"$K8S_CA_CERT\" \
    disable_iss_validation=true
"

# Create policy
echo "4. Creating external-secrets policy..."
kubectl exec -n $VAULT_NS vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault policy write external-secrets - <<EOF
path \"secret/data/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"secret/metadata/*\" {
  capabilities = [\"read\", \"list\"]
}
EOF
"

# Create role
echo "5. Creating Kubernetes auth role..."
kubectl exec -n $VAULT_NS vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets-vault-auth \
    bound_service_account_namespaces=$ESO_NS \
    policies=external-secrets \
    ttl=24h
"

echo ""
echo "✓ Vault authentication fixed!"
echo ""
echo "Verifying configuration..."
kubectl exec -n $VAULT_NS vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault read auth/kubernetes/role/external-secrets
"

echo ""
echo "Restart External Secrets Operator to apply changes:"
echo "  kubectl rollout restart deployment -n $ESO_NS -l app.kubernetes.io/name=external-secrets"
