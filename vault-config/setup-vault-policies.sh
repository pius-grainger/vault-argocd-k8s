#!/bin/bash

# Vault Policy Setup Script
# Run this after Vault is unsealed and initialized

set -e

VAULT_ADDR="${VAULT_ADDR:-https://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Function to create a policy
create_policy() {
  local policy_name=$1
  local policy_rules=$2
  
  echo "Creating policy: $policy_name"
  echo "$policy_rules" | vault policy write "$policy_name" -
}

# External Secrets Operator Policy
# This policy allows ESO to read secrets from Vault
ESO_POLICY='
path "secret/data/applications/*" {
  capabilities = ["read", "list"]
}

path "secret/data/databases/*" {
  capabilities = ["read", "list"]
}

path "secret/data/credentials/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/applications/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/databases/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/credentials/*" {
  capabilities = ["read", "list"]
}
'

# Kubernetes Auth Policy
# This policy is for Kubernetes service account auth
K8S_AUTH_POLICY='
path "auth/kubernetes/login" {
  capabilities = ["create", "read"]
}

path "secret/data/applications/*" {
  capabilities = ["read", "list"]
}

path "secret/data/databases/*" {
  capabilities = ["read", "list"]
}

path "secret/data/credentials/*" {
  capabilities = ["read", "list"]
}
'

# Create policies
create_policy "external-secrets" "$ESO_POLICY"
create_policy "k8s-auth" "$K8S_AUTH_POLICY"

# Enable KV V2 secret engine if not already enabled
echo "Enabling KV V2 secret engine at secret/"
vault secrets enable -path=secret kv-v2 || echo "KV V2 already enabled"

# Enable Kubernetes auth method if not already enabled
echo "Enabling Kubernetes auth method"
vault auth enable kubernetes || echo "Kubernetes auth already enabled"

# Create sample secrets for testing
echo "Creating sample secrets..."

vault kv put secret/applications/demo-app \
  username="demo-user" \
  password="demo-password" \
  api_key="demo-api-key-12345"

vault kv put secret/databases/postgres \
  host="postgres.default.svc.cluster.local" \
  port="5432" \
  username="postgres" \
  password="your-secure-password" \
  database="myapp"

vault kv put secret/credentials/docker-registry \
  username="docker-user" \
  password="docker-password" \
  server="docker.io"

echo "Vault policies and secrets configured successfully!"
