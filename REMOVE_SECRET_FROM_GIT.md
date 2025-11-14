# Remove Secret from Git History

GitHub detected a Vault token in commit `5f2033cfe90d0bc8aa226f9b5bfc27896e83fe36`.

## Option 1: Amend Last Commit (if it's the most recent)

```bash
# Stage the fixed file
git add vault-config/test-vault-setup.sh

# Amend the commit
git commit --amend --no-edit

# Force push
git push --force
```

## Option 2: Rewrite History (if there are commits after it)

```bash
# Use BFG Repo-Cleaner (recommended)
# Install: brew install bfg (macOS) or download from https://rtyley.github.io/bfg-repo-cleaner/

# Replace the token in all history
bfg --replace-text <(echo 'YOUR_EXPOSED_TOKEN==>***REMOVED***')

# Clean up
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force push
git push --force
```

## Option 3: Interactive Rebase

```bash
# Find the commit
git log --oneline | grep -i vault

# Rebase from before that commit
git rebase -i <commit-before-the-bad-one>

# Mark the commit as 'edit', save and close
# Then fix the file
git add vault-config/test-vault-setup.sh
git commit --amend --no-edit
git rebase --continue

# Force push
git push --force
```

## Option 4: Allow the Secret (if it's already rotated)

If you've already rotated the Vault root token, you can allow the push:
1. Click the GitHub URL provided in the error
2. Mark the secret as safe to push

## After Fixing

**IMPORTANT:** Rotate the exposed Vault root token:

```bash
# Generate new root token
kubectl exec -n vault vault-0 -- vault token create -policy=root

# Revoke old token
kubectl exec -n vault vault-0 -- vault token revoke <OLD_TOKEN>
```
