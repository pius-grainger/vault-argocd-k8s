#!/bin/bash
set -e

VAULT_TOKEN="***REMOVED***"
TEST_NS="vault-test"

echo "=== Testing Vault Setup ==="
echo ""

# 1. Create test namespace
echo "1. Creating test namespace..."
kubectl create namespace $TEST_NS --dry-run=client -o yaml | kubectl apply -f -

# 2. Write test secret to Vault
echo "2. Writing test secret to Vault..."
kubectl exec -n vault vault-0 -- sh -c "
  export VAULT_TOKEN=$VAULT_TOKEN
  vault kv put secret/test/myapp username=testuser password=testpass123 api_key=abc123xyz
"

# 3. Create ExternalSecret
echo "3. Creating ExternalSecret..."
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: $TEST_NS
spec:
  secretStoreRef:
    name: vault-backend-cluster
    kind: ClusterSecretStore
  target:
    name: test-secret
    creationPolicy: Owner
  refreshInterval: 10s
  data:
  - secretKey: username
    remoteRef:
      key: test/myapp
      property: username
  - secretKey: password
    remoteRef:
      key: test/myapp
      property: password
  - secretKey: api_key
    remoteRef:
      key: test/myapp
      property: api_key
EOF

# 4. Wait and check
echo "4. Waiting for secret sync..."
sleep 5

# 5. Verify ExternalSecret status
echo "5. Checking ExternalSecret status..."
STATUS=$(kubectl get externalsecret test-secret -n $TEST_NS -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$STATUS" == "True" ]; then
  echo "   ✓ ExternalSecret is Ready"
else
  echo "   ✗ ExternalSecret is NOT Ready"
  kubectl describe externalsecret test-secret -n $TEST_NS
  exit 1
fi

# 6. Verify Kubernetes secret exists
echo "6. Checking Kubernetes secret..."
if kubectl get secret test-secret -n $TEST_NS &>/dev/null; then
  echo "   ✓ Secret exists"
  KEYS=$(kubectl get secret test-secret -n $TEST_NS -o jsonpath='{.data}' | jq -r 'keys | length')
  echo "   ✓ Secret has $KEYS keys"
else
  echo "   ✗ Secret does not exist"
  exit 1
fi

# 7. Verify secret data
echo "7. Verifying secret data..."
USERNAME=$(kubectl get secret test-secret -n $TEST_NS -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl get secret test-secret -n $TEST_NS -o jsonpath='{.data.password}' | base64 -d)
API_KEY=$(kubectl get secret test-secret -n $TEST_NS -o jsonpath='{.data.api_key}' | base64 -d)

if [ "$USERNAME" == "testuser" ] && [ "$PASSWORD" == "testpass123" ] && [ "$API_KEY" == "abc123xyz" ]; then
  echo "   ✓ Secret data is correct"
  echo "     username: $USERNAME"
  echo "     password: $PASSWORD"
  echo "     api_key: $API_KEY"
else
  echo "   ✗ Secret data is incorrect"
  exit 1
fi

# 8. Test with a pod
echo "8. Testing secret in a pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: $TEST_NS
spec:
  containers:
  - name: test
    image: busybox:latest
    command: ['sh', '-c', 'echo "Username: \$USERNAME" && echo "Password: \$PASSWORD" && sleep 10']
    env:
    - name: USERNAME
      valueFrom:
        secretKeyRef:
          name: test-secret
          key: username
    - name: PASSWORD
      valueFrom:
        secretKeyRef:
          name: test-secret
          key: password
  restartPolicy: Never
EOF

sleep 3
kubectl wait --for=condition=Ready pod/test-pod -n $TEST_NS --timeout=30s || true
kubectl logs test-pod -n $TEST_NS

echo ""
echo "=== TEST PASSED ✓ ==="
echo ""
echo "Cleanup:"
echo "  kubectl delete namespace $TEST_NS"
