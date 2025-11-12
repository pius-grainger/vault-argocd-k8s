Vault Auto-unseal (AWS KMS) — Runbook

This document shows how to enable Vault auto-unseal with AWS KMS and provides a short runbook for manual init/unseal steps you ran.

Summary
- We updated the ArgoCD `vault` Application Helm values to include an example `seal "awskms"` block inside `server.ha.raft.config`.
- This is intentionally parameterized: replace <AWS_REGION> and <KMS_KEY_ID> with your values.
- For production, prefer using IRSA (IAM Roles for Service Accounts) so Vault can call KMS without embedding AWS creds.

Steps to enable auto-unseal
1. Create an AWS KMS symmetric key (alias or key id) in the desired region.
   Example (AWS CLI):

```sh
aws kms create-key --description "Vault auto-unseal key" --region eu-west-2
# Note the KeyId (or use an alias)
```

2. Allow the Vault nodes to call KMS. Recommended: create an IAM role and attach it to the nodes (or use IRSA for EKS):
   - IRSA: create an IAM policy allowing kms:Decrypt/kms:GenerateDataKey and attach to the Vault service account.
   - Node IAM role: attach policy to the EC2 instance profile.

Example simpler policy (restrict to kms:Decrypt and kms:GenerateDataKey on the key):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:<AWS_REGION>:<ACCOUNT_ID>:key/<KMS_KEY_ID>"
    }
  ]
}
```

3. Update the ArgoCD `vault` Application values (already applied as a placeholder in `argocd-apps/vault-app.yaml`). Replace the placeholders with your real values:

- <AWS_REGION> — the region where your KMS key exists (e.g., `eu-west-2`).
- <KMS_KEY_ID> — the KMS KeyId or ARN.

4. If using IRSA, ensure the service account `vault` has the IAM role annotation and the proper policy.

5. Sync the ArgoCD application or redeploy the chart so the HCL config with the `seal "awskms"` block is rendered into the Vault configuration.

Manual init/unseal runbook (what you executed)
- Initialize Vault on the leader (one-time):

```sh
kubectl exec -n vault -it vault-0 -- vault operator init -key-shares=5 -key-threshold=3
# Save the Unseal Keys and Initial Root Token in a secure place (not in git)
```

- Unseal the leader and standbys (example using three keys):

```sh
# Unseal each pod (run on each pod):
kubectl exec -n vault -it vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault -it vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault -it vault-0 -- vault operator unseal <UNSEAL_KEY_3>

# Repeat for vault-1 and vault-2 (standbys) after they join the raft cluster:
kubectl exec -n vault -it vault-1 -- vault operator unseal <UNSEAL_KEY_1>
...
```

Post-deployment housekeeping
- Rotate the initial root token and store unseal keys securely (consider using a sealed-systems safe or offline storage).
- Configure monitoring and alerts for seal/unseal and Raft replication.
- Consider enabling AWS KMS auto-unseal in the chart (as above) so manual unseal is not required on restarts.

If you'd like, I can:
- Replace the placeholder `<AWS_REGION>` and `<KMS_KEY_ID>` in `argocd-apps/vault-app.yaml` with concrete values you provide.
- Add an example IRSA service account annotation in the Helm values and a sample IAM policy file in the repo.

Which of those would you like me to do next?