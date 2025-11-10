#!/bin/bash

# Advanced Vault Configuration Script
# Includes secret rotation, auto-unsealing, and advanced policies

set -e

VAULT_ADDR="${VAULT_ADDR:-https://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

echo "=========================================="
echo "Advanced Vault Configuration"
echo "=========================================="

# Function to setup secret rotation
setup_secret_rotation() {
  echo "Setting up secret rotation policy..."
  
  # Policy allowing rotation operations
  ROTATION_POLICY='
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

path "secret/data/*" {
  capabilities = ["read", "list"]
}
'
  
  echo "$ROTATION_POLICY" | vault policy write rotation -
}

# Function to enable database secrets engine (example)
setup_database_secrets() {
  echo "Configuring database secrets engine..."
  
  # Enable database secrets engine
  vault secrets enable database || echo "Database secrets already enabled"
  
  # Configure PostgreSQL connection
  vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="readonly" \
    connection_url="postgresql://{{username}}:{{password}}@postgres.default.svc.cluster.local:5432/postgres" \
    username="postgres" \
    password="initial-password" || echo "PostgreSQL config already exists"
  
  # Create role for read-only access
  vault write database/roles/readonly \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h" || echo "PostgreSQL role already exists"
}

# Function to setup SSH secrets engine
setup_ssh_secrets() {
  echo "Configuring SSH secrets engine..."
  
  vault secrets enable ssh || echo "SSH secrets already enabled"
  
  # Create SSH CA role
  vault write ssh/roles/ca \
    key_type=ca \
    ttl=30m \
    max_ttl=2h \
    allowed_users="*" || echo "SSH CA role already exists"
}

# Function to enable transit engine for encryption
setup_transit_engine() {
  echo "Configuring transit engine for encryption..."
  
  vault secrets enable transit || echo "Transit engine already enabled"
  
  # Create encryption key
  vault write -f transit/keys/applications || echo "Transit key already exists"
  
  # Create policy for transit operations
  TRANSIT_POLICY='
path "transit/encrypt/applications" {
  capabilities = ["update"]
}

path "transit/decrypt/applications" {
  capabilities = ["update"]
}
'
  
  echo "$TRANSIT_POLICY" | vault policy write transit -
}

# Function to setup audit logging
setup_audit_logging() {
  echo "Configuring audit logging..."
  
  # Enable file audit backend
  vault audit enable file file_path=/vault/logs/audit.log || echo "File audit already enabled"
  
  # Enable syslog audit backend (optional)
  # vault audit enable syslog tag="vault" facility="LOCAL7" || echo "Syslog audit already enabled"
}

# Function to setup OIDC/JWT auth (optional)
setup_jwt_auth() {
  echo "Configuring JWT auth method..."
  
  vault auth enable jwt || echo "JWT auth already enabled"
  
  # Example: Configure OIDC provider
  # vault write auth/jwt/config \
  #   oidc_discovery_url="https://your-oidc-provider.com" \
  #   oidc_client_id="your-client-id" \
  #   oidc_client_secret="your-client-secret"
}

# Function to setup advanced AppRole
setup_approle_auth() {
  echo "Configuring AppRole auth method..."
  
  vault auth enable approle || echo "AppRole auth already enabled"
  
  # Create AppRole for automated deployments
  vault write auth/approle/role/automation-role \
    token_num_uses=0 \
    token_ttl=1h \
    token_max_ttl=24h \
    policies="external-secrets,k8s-auth"
  
  # Get role ID
  ROLE_ID=$(vault read -field=role_id auth/approle/role/automation-role/role-id)
  echo "AppRole Role ID: $ROLE_ID"
}

# Function to setup auto-unseal (requires KMS)
setup_auto_unseal() {
  echo "Setting up auto-unseal configuration (reference)..."
  echo "Note: Auto-unseal requires AWS KMS, Azure Key Vault, or similar"
  echo "Add to vault-config.hcl:"
  echo ""
  echo 'seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "12345678-1234-1234-1234-123456789012"
}'
}

# Function to setup replication (Enterprise)
setup_replication() {
  echo "Setting up replication (Enterprise feature)..."
  echo "Note: Replication requires Vault Enterprise"
  echo "Commands:"
  echo "  vault write -f sys/replication/dr/primary/enable"
  echo "  vault write -f sys/replication/performance/primary/enable"
}

# Run all setups
echo ""
echo "Choose what to configure:"
echo "1. All (default)"
echo "2. Rotation only"
echo "3. Database secrets"
echo "4. SSH secrets"
echo "5. Transit engine"
echo "6. Audit logging"
echo ""
read -p "Enter choice [1-6] (default: 1): " choice
choice=${choice:-1}

case $choice in
  1)
    setup_secret_rotation
    setup_database_secrets
    setup_ssh_secrets
    setup_transit_engine
    setup_audit_logging
    setup_approle_auth
    setup_auto_unseal
    ;;
  2)
    setup_secret_rotation
    ;;
  3)
    setup_database_secrets
    ;;
  4)
    setup_ssh_secrets
    ;;
  5)
    setup_transit_engine
    ;;
  6)
    setup_audit_logging
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "Advanced configuration complete!"
