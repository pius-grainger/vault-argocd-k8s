# Using Vault Secrets in Your Applications

This guide shows how to integrate secrets from Vault into your Kubernetes applications using the External Secrets Operator.

## Overview

You have two main approaches to consume Vault secrets in your applications:

### 1. **External Secrets Operator (ESO)** ✅ Recommended
- Syncs secrets from Vault to Kubernetes Secrets
- Applications read from standard Kubernetes Secrets
- No Vault client library needed in your app
- Easier for existing applications

### 2. **Vault Agent Injector**
- Injects secrets directly into pod filesystem/memory
- Real-time secret updates
- Better for ephemeral secrets
- Requires pod annotations

---

## Approach 1: Using External Secrets (Recommended)

### How It Works

```
Vault (secret/data/...) 
    ↓
External Secrets Operator 
    ↓
Kubernetes Secret 
    ↓
Your Application
```

### Step 1: Create an ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  # Reference the ClusterSecretStore we created
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend-cluster
  
  # Define which Vault secrets to sync
  data:
  - secretKey: username          # Key in the Kubernetes Secret
    remoteRef:
      key: applications/my-app   # Path in Vault
      property: username         # Field in the Vault secret
  
  - secretKey: password
    remoteRef:
      key: applications/my-app
      property: password
  
  # Target: the Kubernetes Secret that will be created
  target:
    name: my-app-secrets
    creationPolicy: Owner
```

### Step 2: Use in Your Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
        # Reference the synced Kubernetes Secret
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: my-app-secrets
              key: username
        
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-app-secrets
              key: password
        
        # Or mount as files
        volumeMounts:
        - name: secrets
          mountPath: /etc/secrets
          readOnly: true
      
      volumes:
      - name: secrets
        secret:
          secretName: my-app-secrets
```

### Step 3: Access in Your Application

**As Environment Variables:**
```python
import os
username = os.getenv('DB_USERNAME')
password = os.getenv('DB_PASSWORD')
```

**As Files:**
```python
with open('/etc/secrets/username') as f:
    username = f.read().strip()
```

---

## Approach 2: Using Vault Agent Injector

### Prerequisites

The Vault Agent Injector must be installed (it is in your setup).

### Step 1: Annotate Your Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        # Enable injection for this pod
        vault.hashicorp.com/agent-inject: "true"
        
        # The Kubernetes auth role to use
        vault.hashicorp.com/role: "application"
        
        # Inject a secret as environment variables
        vault.hashicorp.com/agent-inject-secret-database: "secret/data/databases/postgres"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "secret/data/databases/postgres" -}}
          export DB_HOST="{{ .Data.data.host }}"
          export DB_USER="{{ .Data.data.username }}"
          export DB_PASSWORD="{{ .Data.data.password }}"
          {{- end }}
        
        # Inject another secret as a JSON file
        vault.hashicorp.com/agent-inject-secret-app: "secret/data/applications/demo-app"
        vault.hashicorp.com/agent-inject-file-app: "app-config.json"
        vault.hashicorp.com/agent-inject-template-app: |
          {{- with secret "secret/data/applications/demo-app" -}}
          {
            "username": "{{ .Data.data.username }}",
            "password": "{{ .Data.data.password }}",
            "api_key": "{{ .Data.data.api_key }}"
          }
          {{- end }}
    spec:
      serviceAccountName: default
      containers:
      - name: app
        image: myapp:latest
        # Inject environment variables from agent
        command: 
        - /bin/sh
        - -c
        - |
          . /vault/secrets/database  # Source env vars
          exec myapp
```

### Step 2: Access Secrets in Your Application

**From sourced environment variables:**
```bash
. /vault/secrets/database  # Load env vars
echo $DB_HOST
echo $DB_USER
```

**From injected files:**
```python
import json
with open('/vault/secrets/app-config.json') as f:
    config = json.load(f)
    username = config['username']
```

---

## Comparison: External Secrets vs Agent Injector

| Feature | External Secrets | Agent Injector |
|---------|------------------|----------------|
| **Setup Complexity** | Simple | Moderate |
| **Secret Storage** | Kubernetes Secret | Pod filesystem/memory |
| **Update Frequency** | Periodic (default 1h) | Real-time |
| **Secret Rotation** | Manual redeployment | Automatic |
| **Requires Vault in Pod** | No | Yes (agent sidecar) |
| **Best For** | Static secrets, existing apps | Dynamic secrets, real-time updates |

---

## Working Example: Alpine App (Test)

A working example is deployed in the production namespace:

```bash
# View logs showing secrets in action
kubectl logs -n production -l app=demo-app-working

# Output will show:
# Application Secrets (from app-secrets):
#   Username: demo-user
#   Password: demo-password
#   API Key: demo-api-key-12345
```

---

## Creating Secrets in Vault

Before creating ExternalSecrets, add your secrets to Vault:

### Via `vault` CLI (from vault-0 pod):

```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &

# Authenticate (use root token from initialization - store securely offline)
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=<YOUR_ROOT_TOKEN>

# Create application secrets
vault kv put secret/applications/my-app \
  username="app-user" \
  password="app-password" \
  api_key="secret-key-123"

# Create database secrets
vault kv put secret/databases/mydb \
  host="postgres.default.svc.cluster.local" \
  port=5432 \
  username="dbuser" \
  password="dbpass" \
  database="myapp"

# List secrets
vault kv list secret/applications/
vault kv get secret/applications/my-app
```

---

## Troubleshooting

### ExternalSecret not syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Check logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Verify SecretStore is Ready
kubectl get secretstore -A
```

### Secret not appearing in pod

```bash
# Check if Kubernetes Secret was created
kubectl get secret <secret-name> -n <namespace>

# View secret data
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}'

# Check pod environment
kubectl exec -it <pod> -n <namespace> -- env | grep DB_
```

### Agent Injector not working

```bash
# Verify agent injector is running
kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector

# Check pod annotations
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations}' | jq

# View agent logs
kubectl logs <pod-name> -c vault-agent -n <namespace>
```

---

## Next Steps

1. **Create your own secrets** in Vault using the CLI above
2. **Create ExternalSecrets** for your applications
3. **Update your Deployments** to mount the secrets
4. **Test by deploying** an application
5. **Monitor** using the validation script: `bash vault-config/validate-deployment.sh`

---

## Security Best Practices

- ✅ Use **least-privilege policies** per application
- ✅ **Rotate secrets** regularly (implement secret rotation jobs)
- ✅ **Enable TLS** for Vault communication (see README-unseal.md)
- ✅ **Audit logs** for all secret access
- ✅ **RBAC policies** to control who can create/update ExternalSecrets
- ✅ Keep **unseal keys offline** in secure storage

---

For more details, see:
- [External Secrets Operator Docs](https://external-secrets.io/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
