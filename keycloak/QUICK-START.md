# Quick Start - Keycloak Deployment

## Fix Permission Errors

If you're seeing errors like:
```
deployments.apps is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource
secrets is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource
services is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource
Route.route.openshift.io "keycloak" is invalid: spec.host: Forbidden: you do not have permission to set the host field
```

**Apply the RBAC configuration:**

```bash
oc apply -f argocd-rbac.yaml
```

This grants ArgoCD permissions to manage all Keycloak resources including:
- ✅ Deployments
- ✅ Secrets
- ✅ Services
- ✅ ConfigMaps
- ✅ Keycloak CRDs
- ✅ Operators (OLM)
- ✅ Routes (including custom hostnames)
- ✅ Batch Jobs
- ✅ And more...

## Verify RBAC Applied

```bash
# Check ClusterRole
oc get clusterrole argocd-keycloak-manager

# Check ClusterRoleBinding
oc get clusterrolebinding argocd-keycloak-manager

# Verify it's bound to ArgoCD service account
oc describe clusterrolebinding argocd-keycloak-manager
```

## Deploy After RBAC is Applied

Once RBAC is applied, ArgoCD can successfully create all resources.

### Option 1: Deploy Everything
```bash
oc apply -f platform-parent-app.yaml
```

### Option 2: Deploy Infrastructure Only
```bash
oc apply -f infra/parent-app.yaml
```

### Option 3: Deploy Tenant Only
```bash
oc apply -f tenant/parent-app.yaml
```

## Monitor Deployment

```bash
# Watch ArgoCD applications
watch oc get applications -n openshift-gitops

# Check specific app status
oc describe application keycloak-operator -n openshift-gitops

# View deployed resources
oc get all -n keycloak
```

## Troubleshooting

### Still Getting Permission Errors?

1. **Verify RBAC is applied:**
   ```bash
   oc get clusterrolebinding argocd-keycloak-manager -o yaml
   ```

2. **Check the service account name:**
   The binding should reference `openshift-gitops-argocd-application-controller` in namespace `openshift-gitops`.

3. **Restart ArgoCD application controller:**
   ```bash
   oc rollout restart deployment openshift-gitops-application-controller -n openshift-gitops
   ```

### Different ArgoCD Namespace?

If your ArgoCD is in a different namespace (not `openshift-gitops`), edit `argocd-rbac.yaml`:

```yaml
subjects:
  - kind: ServiceAccount
    name: <your-argocd-app-controller-sa>
    namespace: <your-argocd-namespace>
```

Then reapply:
```bash
oc apply -f argocd-rbac.yaml
```

## Next Steps

See [ARGOCD-SETUP.md](ARGOCD-SETUP.md) for complete deployment guide.
