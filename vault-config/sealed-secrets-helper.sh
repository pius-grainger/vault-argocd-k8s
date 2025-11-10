#!/bin/bash

# Sealed Secrets Helper Script
# Use this to encrypt secrets for Git storage

set -e

SEALED_SECRETS_NS="sealed-secrets"
SEALED_SECRETS_NAME="sealed-secrets"

echo "=========================================="
echo "Sealed Secrets Helper"
echo "=========================================="

# Function to encode secret
encode_secret() {
  local namespace=$1
  local secret_name=$2
  local key=$3
  local value=$4
  
  echo "Encoding secret $secret_name in namespace $namespace..."
  
  # Create a temporary secret
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: temp-secret
  namespace: $namespace
type: Opaque
stringData:
  $key: $value
EOF
  
  # Get the encoded value
  ENCODED=$(kubectl get secret temp-secret -n $namespace -o jsonpath='{.data}' | jq -r ".[\"$key\"]" | base64 -d)
  
  # Delete the temporary secret
  kubectl delete secret temp-secret -n $namespace
  
  echo "Encoded: $ENCODED"
}

# Function to seal a secret
seal_secret() {
  local namespace=$1
  local secret_name=$2
  local key=$3
  local value=$4
  
  echo "Sealing secret $secret_name in namespace $namespace..."
  
  # Create a secret manifest
  cat > /tmp/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: $namespace
type: Opaque
stringData:
  $key: $value
EOF
  
  # Seal it
  kubeseal -f /tmp/secret.yaml -w /tmp/sealed-secret.yaml \
    --scope namespace \
    -n $namespace
  
  echo "Sealed secret saved to /tmp/sealed-secret.yaml"
  echo "Content:"
  cat /tmp/sealed-secret.yaml
  
  # Cleanup
  rm /tmp/secret.yaml
}

# Function to unseal (for reference)
unseal_secret() {
  echo "To unseal a secret (for testing):"
  echo "kubectl logs -l app.kubernetes.io/name=sealed-secrets -n $SEALED_SECRETS_NS --tail=50"
}

# Function to get sealing public key
get_public_key() {
  echo "Retrieving Sealed Secrets public key..."
  kubectl get secret -n $SEALED_SECRETS_NS sealing-key-* -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > ~/sealed-secrets-public.crt
  echo "Public key saved to ~/sealed-secrets-public.crt"
}

# Function to list all sealed secrets
list_sealed_secrets() {
  echo "Listing all SealedSecrets:"
  kubectl get sealedsecrets -A
}

# Interactive menu
show_menu() {
  echo ""
  echo "1. Seal a secret"
  echo "2. Encode secret"
  echo "3. Get public key"
  echo "4. List sealed secrets"
  echo "5. Unseal reference"
  echo "6. Exit"
  echo ""
  read -p "Enter choice [1-6]: " choice
}

# Main loop
while true; do
  show_menu
  
  case $choice in
    1)
      read -p "Enter namespace: " ns
      read -p "Enter secret name: " sname
      read -p "Enter key: " key
      read -p "Enter value: " value
      seal_secret "$ns" "$sname" "$key" "$value"
      ;;
    2)
      read -p "Enter namespace: " ns
      read -p "Enter secret name: " sname
      read -p "Enter key: " key
      read -p "Enter value: " value
      encode_secret "$ns" "$sname" "$key" "$value"
      ;;
    3)
      get_public_key
      ;;
    4)
      list_sealed_secrets
      ;;
    5)
      unseal_secret
      ;;
    6)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
done
