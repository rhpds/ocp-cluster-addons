# ArgoCD Setup for Keycloak Deployment

This guide explains how to set up ArgoCD permissions and deploy the Keycloak platform.

## Prerequisites

1. **OpenShift GitOps (ArgoCD) installed**
   ```bash
   # Check if ArgoCD is installed
   oc get pods -n openshift-gitops
   ```

2. **Cluster admin access** to create ClusterRole and ClusterRoleBinding

## Step 1: Grant ArgoCD Permissions

ArgoCD needs permissions to manage resources in the target namespaces. Apply the RBAC configuration:

```bash
oc apply -f argocd-rbac.yaml
```

This creates:
- **ClusterRole** `argocd-keycloak-manager` - Permissions to manage Keycloak resources
- **ClusterRoleBinding** `argocd-keycloak-manager` - Binds role to ArgoCD service account

### What Permissions Are Granted?

The ClusterRole grants the ArgoCD application controller permission to:
- Manage Keycloak CRDs (Keycloak, KeycloakRealmImport, KeycloakUser)
- Create/manage namespaces, secrets, configmaps, services
- Deploy applications (Deployments, StatefulSets)
- Configure RBAC (Roles, RoleBindings)
- Manage OLM operators (Subscriptions, OperatorGroups, InstallPlans)
- Configure OpenShift OAuth
- Create Routes (OpenShift ingress)
- Run Jobs (for InstallPlan approver)

### Verify Permissions

```bash
# Check if ClusterRole was created
oc get clusterrole argocd-keycloak-manager

# Check if ClusterRoleBinding was created
oc get clusterrolebinding argocd-keycloak-manager

# Verify the service account exists
oc get sa openshift-gitops-argocd-application-controller -n openshift-gitops
```

## Step 2: Configure Deployment

Run the configuration script to set up your deployment:

```bash
./configure.sh
```

The script will:
1. Ask what to deploy (infrastructure, tenant, or both)
2. Collect configuration values
3. Update Git repository URLs in ArgoCD app manifests
4. Update Helm chart values
5. Save credentials to `credentials.txt`

## Step 3: Commit Configuration to Git

```bash
# Add changed files
git add infra/ tenant/ platform-parent-app.yaml argocd-rbac.yaml

# Commit
git commit -m "Configure Keycloak deployment"

# Push to your repository
git push
```

## Step 4: Deploy

### Option A: Deploy Everything (Infrastructure + Tenant)

```bash
oc apply -f platform-parent-app.yaml
```

### Option B: Deploy Infrastructure Only

```bash
oc apply -f infra/parent-app.yaml
```

This deploys:
- Keycloak operator
- PostgreSQL database
- Keycloak instance
- Keycloak realm
- OpenShift OAuth integration

### Option C: Deploy Tenant Only

```bash
oc apply -f tenant/parent-app.yaml
```

This deploys:
- Keycloak users
- Namespaces
- RBAC bindings

**Note:** Requires infrastructure to be deployed first.

## Step 5: Monitor Deployment

### Via ArgoCD UI

```bash
# Get ArgoCD route
oc get route openshift-gitops-server -n openshift-gitops

# Get admin password
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
```

Access the ArgoCD UI and watch the applications sync.

### Via CLI

```bash
# Watch all Keycloak apps
watch oc get applications -n openshift-gitops | grep keycloak

# Check specific app
oc get application keycloak-operator -n openshift-gitops -o yaml

# View sync status
oc describe application keycloak-operator -n openshift-gitops
```

### Check Deployed Resources

```bash
# Infrastructure
oc get pods -n keycloak
oc get keycloak -n keycloak
oc get route -n keycloak

# Tenant
oc get keycloakuser -n keycloak
oc get namespaces | grep <tenant-guid>
```

## Troubleshooting

### Permission Errors

**Error:** `User "system:serviceaccount:openshift-gitops:..." cannot create resource`

**Solution:** Ensure `argocd-rbac.yaml` is applied:
```bash
oc apply -f argocd-rbac.yaml
```

### App Not Syncing

**Check sync status:**
```bash
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.sync.status}'
```

**Force sync:**
```bash
# Via ArgoCD CLI
argocd app sync <app-name>

# Via kubectl
oc patch application <app-name> -n openshift-gitops --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Invalid Git Path

**Error:** `path 'argocd/...' not found in repository`

**Solution:** Ensure all ArgoCD Application manifests use correct paths:
- Infrastructure charts: `keycloak/infra/charts/*`
- Tenant charts: `keycloak/tenant/charts/*`
- App directories: `keycloak/infra/apps` and `keycloak/tenant/apps`

### Operator Installation Fails

Check InstallPlan:
```bash
oc get installplan -n keycloak
oc describe installplan <name> -n keycloak
```

If using manual approval with InstallPlan approver, check job logs:
```bash
oc logs -n keycloak job/rhbk-operator-installplan-approver
```

## Cleanup

### Remove Everything

```bash
# Delete platform app (removes all child apps)
oc delete application keycloak-platform -n openshift-gitops

# Or delete individually
oc delete application keycloak-infra -n openshift-gitops
oc delete application keycloak-tenants -n openshift-gitops

# Remove RBAC
oc delete -f argocd-rbac.yaml
```

### Remove Just Tenant

```bash
oc delete application keycloak-tenants -n openshift-gitops
```

### Keep Infrastructure, Remove Tenant

```bash
# Delete tenant app
oc delete application keycloak-tenants -n openshift-gitops

# Manually clean up tenant resources if needed
oc delete keycloakuser --all -n keycloak
oc delete namespace <tenant-namespace>
```

## Next Steps

- Review deployed resources in ArgoCD UI
- Test Keycloak login at `https://sso.<your-domain>`
- Test OpenShift OAuth with Keycloak users
- Configure additional tenants (see `tenant/examples/`)
- Set up monitoring and alerts

## See Also

- [Infrastructure README](infra/README.md)
- [Tenant README](tenant/README.md)
- [CSV Pinning Feature](CSV-PINNING-FEATURE.md)
- [Operator Chart README](infra/charts/keycloak-operator/README.md)
