# Quick Start Guide

This is a quick reference for deploying Keycloak with ArgoCD.

## Prerequisites

```bash
# Ensure you're logged in to OpenShift
oc whoami

# Ensure OpenShift GitOps is installed
oc get pods -n openshift-gitops
```

## Quick Deploy (5 minutes)

### 1. Configure (Automated)

```bash
cd argocd
./configure.sh
```

This script will:
- Prompt for your Git repository URL
- Auto-detect your OpenShift ingress domain
- Generate secure random passwords
- Update all configuration files
- Save credentials to `credentials.txt`

### 2. Commit and Push

```bash
git add .
git commit -m "Configure Keycloak deployment"
git push
```

### 3. Deploy

```bash
# Deploy the parent app (deploys all child apps)
oc apply -f parent-app.yaml

# Watch the deployment
watch oc get applications -n openshift-gitops
```

### 4. Verify

```bash
# Check all apps are synced and healthy
oc get applications -n openshift-gitops

# Check Keycloak is running
oc get keycloak -n keycloak
oc get pods -n keycloak

# Get the Keycloak URL
echo "https://sso.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
```

### 5. Login

```bash
# View your credentials
cat credentials.txt

# Login to OpenShift console with Keycloak
oc login --username=admin --password=<from credentials.txt>
```

## Manual Configuration

If you prefer manual configuration:

### 1. Update Git Repository

Edit all files in `apps/` and `parent-app.yaml`:
```yaml
repoURL: https://github.com/YOUR-ORG/YOUR-REPO.git
targetRevision: main
```

### 2. Update Ingress Domain

Get your domain:
```bash
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
```

Update in:
- `charts/keycloak-instance/values.yaml`
- `charts/keycloak-oauth/values.yaml`

```yaml
ingressDomain: apps.your-cluster.example.com
```

### 3. Update Passwords

Update in these files:
- `charts/keycloak-postgres/values.yaml` - PostgreSQL password
- `charts/keycloak-realm/values.yaml` - OAuth secret, admin password, user password
- `charts/keycloak-oauth/values.yaml` - OAuth secret (must match realm)

### 4. Deploy

```bash
oc apply -f parent-app.yaml
```

## Troubleshooting

### Apps not syncing?

```bash
# Check ArgoCD application status
oc get applications -n openshift-gitops

# Check specific app
oc describe application keycloak-instance -n openshift-gitops

# Force sync
argocd app sync keycloak-instance --force
```

### Operator not installing?

```bash
# Check subscription
oc get subscription rhbk-operator -n keycloak

# Check CSV
oc get csv -n keycloak | grep rhbk

# Check operator pod
oc get pods -n keycloak | grep operator
```

### Keycloak not starting?

```bash
# Check Keycloak CR
oc get keycloak -n keycloak -o yaml

# Check pods
oc get pods -n keycloak

# Check logs
oc logs -n keycloak keycloak-0
```

### OAuth not working?

```bash
# Check OAuth config
oc get oauth cluster -o yaml

# Check authentication pods
oc get pods -n openshift-authentication

# Restart authentication pods if needed
oc delete pods -n openshift-authentication -l app=oauth-openshift
```

## Common Tasks

### Update number of users

Edit `charts/keycloak-realm/values.yaml`:
```yaml
realm:
  users:
    regular:
      count: 10  # Change this
```

Commit, push, and sync:
```bash
git add charts/keycloak-realm/values.yaml
git commit -m "Update user count"
git push
argocd app sync keycloak-realm
```

### Disable admin user

Edit `charts/keycloak-realm/values.yaml`:
```yaml
realm:
  users:
    admin:
      enabled: false
```

### Change passwords

Edit the respective values.yaml files, commit, and push.
ArgoCD will sync the changes.

### Remove kubeadmin

**WARNING**: Only do this after confirming OAuth works!

Edit `charts/keycloak-oauth/values.yaml`:
```yaml
rbac:
  removeKubeadmin:
    enabled: true
```

## Accessing Keycloak

### Keycloak Admin Console

```bash
# Get Keycloak admin credentials
KC_USER=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)
KC_PASS=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)

echo "Keycloak Admin Console: https://sso.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
echo "Username: $KC_USER"
echo "Password: $KC_PASS"
```

### OpenShift Console

Login with:
- Admin user: `admin` / (from credentials.txt)
- Regular users: `user1`, `user2`, etc. / (from credentials.txt)

## Uninstall

```bash
# Delete the parent app (removes all child apps)
oc delete application keycloak-platform -n openshift-gitops

# Wait for resources to be cleaned up
watch oc get pods -n keycloak

# Reset OAuth (optional)
oc patch oauth cluster --type=json -p='[{"op": "remove", "path": "/spec/identityProviders"}]'

# Delete namespace (optional)
oc delete namespace keycloak
```

## File Reference

- `parent-app.yaml` - Main App of Apps
- `apps/*.yaml` - Child application definitions
- `charts/*/values.yaml` - Configuration for each component
- `README.md` - Full documentation
- `sync-waves.md` - Deployment order details
- `configure.sh` - Interactive configuration script
- `credentials.txt` - Generated credentials (gitignored)

## Getting Help

1. Check `README.md` for detailed documentation
2. Check `sync-waves.md` for deployment order issues
3. Use `oc describe` and `oc logs` for troubleshooting
4. Check ArgoCD UI for sync status

## ArgoCD UI

Access ArgoCD UI:
```bash
# Get ArgoCD route
oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
```
