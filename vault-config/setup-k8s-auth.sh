#!/bin/bash

# Kubernetes Auth Configuration for Vault
# This script configures the Kubernetes auth method in Vault

set -e

VAULT_ADDR="${VAULT_ADDR:-https://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
K8S_HOST="${K8S_HOST:-https://kubernetes.default.svc.cluster.local:443}"
K8S_CACERT="${K8S_CACERT:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}"
K8S_SA_TOKEN="${K8S_SA_TOKEN:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)}"

echo "Configuring Kubernetes Auth method..."
echo "Vault Address: $VAULT_ADDR"
echo "Kubernetes Host: $K8S_HOST"

# Configure the Kubernetes auth method
vault write auth/kubernetes/config \
  token_reviewer_jwt="$K8S_SA_TOKEN" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert=@"$K8S_CACERT" \
  disable_iss_validation=true

# Create a role for external-secrets-operator
echo "Creating Vault role for External Secrets Operator..."
vault write auth/kubernetes/role/external-secrets-operator \
  bound_service_account_names=external-secrets-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h

# Create a role for applications (example)
echo "Creating Vault role for application namespaces..."
vault write auth/kubernetes/role/application \
  bound_service_account_names=default \
  bound_service_account_namespaces="default,production,staging,development" \
  policies=k8s-auth \
  ttl=24h

echo "Kubernetes auth configuration complete!"
