#!/bin/bash

# Disaster Recovery and Backup Script
# Backs up Vault state and ArgoCD configurations

set -e

BACKUP_DIR="${BACKUP_DIR:-.}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VAULT_NS="vault"
ARGOCD_NS="argocd"

echo "=========================================="
echo "Backup and Disaster Recovery"
echo "=========================================="

mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Function to backup Vault
backup_vault() {
  echo "Backing up Vault state..."
  
  # Port-forward to Vault
  kubectl port-forward -n $VAULT_NS svc/vault 8200:8200 > /dev/null 2>&1 &
  PF_PID=$!
  sleep 2
  
  # Take snapshot
  export VAULT_ADDR="https://localhost:8200"
  export VAULT_SKIP_VERIFY=true
  
  if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN not set"
    kill $PF_PID
    return 1
  fi
  
  # Backup KV secrets (example paths)
  vault kv list secret/ > "$BACKUP_DIR/$TIMESTAMP/vault-secret-paths.txt" || true
  
  # Backup policies
  vault policy list > "$BACKUP_DIR/$TIMESTAMP/vault-policies.txt"
  for policy in $(vault policy list | grep -v "^root$"); do
    vault policy read "$policy" > "$BACKUP_DIR/$TIMESTAMP/vault-policy-$policy.hcl"
  done
  
  # Backup auth methods
  vault auth list > "$BACKUP_DIR/$TIMESTAMP/vault-auth-methods.txt"
  
  # Backup Raft snapshot (if using raft storage)
  kubectl exec -it vault-0 -n $VAULT_NS -- \
    vault operator raft snapshot save /tmp/raft.snap || true
  
  kubectl cp $VAULT_NS/vault-0:/tmp/raft.snap "$BACKUP_DIR/$TIMESTAMP/vault-raft.snap" || true
  
  # Cleanup
  kill $PF_PID || true
  
  echo "Vault backup complete: $BACKUP_DIR/$TIMESTAMP"
}

# Function to backup ArgoCD
backup_argocd() {
  echo "Backing up ArgoCD configurations..."
  
  # Export all ArgoCD applications
  kubectl get application -n $ARGOCD_NS -o yaml > "$BACKUP_DIR/$TIMESTAMP/argocd-applications.yaml"
  
  # Export ArgoCD server configuration
  kubectl get cm argocd-cm -n $ARGOCD_NS -o yaml > "$BACKUP_DIR/$TIMESTAMP/argocd-cm.yaml"
  
  # Export repository credentials
  kubectl get secret -n $ARGOCD_NS | grep repository | awk '{print $1}' | while read secret; do
    kubectl get secret "$secret" -n $ARGOCD_NS -o yaml >> "$BACKUP_DIR/$TIMESTAMP/argocd-repos.yaml"
  done
  
  echo "ArgoCD backup complete: $BACKUP_DIR/$TIMESTAMP"
}

# Function to backup External Secrets
backup_external_secrets() {
  echo "Backing up External Secrets Operator configurations..."
  
  # Export all ExternalSecrets
  kubectl get externalsecret -A -o yaml > "$BACKUP_DIR/$TIMESTAMP/external-secrets.yaml"
  
  # Export all SecretStores
  kubectl get secretstore -A -o yaml > "$BACKUP_DIR/$TIMESTAMP/secretstores.yaml"
  kubectl get clustersecretstore -o yaml > "$BACKUP_DIR/$TIMESTAMP/clustersecretstores.yaml"
  
  echo "External Secrets backup complete: $BACKUP_DIR/$TIMESTAMP"
}

# Function to backup namespaces and RBAC
backup_rbac() {
  echo "Backing up RBAC and namespace configurations..."
  
  # Backup namespaces
  kubectl get namespaces -o yaml > "$BACKUP_DIR/$TIMESTAMP/namespaces.yaml"
  
  # Backup RBAC
  kubectl get clusterroles -o yaml > "$BACKUP_DIR/$TIMESTAMP/clusterroles.yaml"
  kubectl get clusterrolebindings -o yaml > "$BACKUP_DIR/$TIMESTAMP/clusterrolebindings.yaml"
  kubectl get roles -A -o yaml > "$BACKUP_DIR/$TIMESTAMP/roles.yaml"
  kubectl get rolebindings -A -o yaml > "$BACKUP_DIR/$TIMESTAMP/rolebindings.yaml"
  
  echo "RBAC backup complete: $BACKUP_DIR/$TIMESTAMP"
}

# Function to restore from backup
restore_backup() {
  local backup_path=$1
  
  if [ ! -d "$backup_path" ]; then
    echo "ERROR: Backup directory not found: $backup_path"
    return 1
  fi
  
  echo "Restoring from backup: $backup_path"
  
  # Restore namespaces
  kubectl apply -f "$backup_path/namespaces.yaml"
  
  # Restore RBAC
  kubectl apply -f "$backup_path/clusterroles.yaml"
  kubectl apply -f "$backup_path/clusterrolebindings.yaml"
  kubectl apply -f "$backup_path/roles.yaml"
  kubectl apply -f "$backup_path/rolebindings.yaml"
  
  # Restore External Secrets configs
  kubectl apply -f "$backup_path/secretstores.yaml"
  kubectl apply -f "$backup_path/clustersecretstores.yaml"
  kubectl apply -f "$backup_path/external-secrets.yaml"
  
  # Restore Vault (manual - requires unsealing)
  echo "Note: Vault restoration requires manual unsealing and secret restoration"
  
  # Restore ArgoCD applications
  kubectl apply -f "$backup_path/argocd-applications.yaml"
  
  echo "Restoration complete!"
}

# Function to list backups
list_backups() {
  echo "Available backups:"
  ls -1 "$BACKUP_DIR"
}

# Main flow
case "${1:-full}" in
  full)
    backup_vault || true
    backup_argocd
    backup_external_secrets
    backup_rbac
    echo ""
    echo "Full backup complete in: $BACKUP_DIR/$TIMESTAMP"
    ;;
  vault)
    backup_vault
    ;;
  argocd)
    backup_argocd
    ;;
  external-secrets)
    backup_external_secrets
    ;;
  rbac)
    backup_rbac
    ;;
  restore)
    if [ -z "$2" ]; then
      echo "ERROR: Please specify backup directory"
      echo "Usage: $0 restore <backup_path>"
      exit 1
    fi
    restore_backup "$2"
    ;;
  list)
    list_backups
    ;;
  *)
    echo "Usage: $0 {full|vault|argocd|external-secrets|rbac|restore <path>|list}"
    exit 1
    ;;
esac

echo "Done!"
