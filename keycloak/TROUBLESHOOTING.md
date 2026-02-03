# Troubleshooting Guide

## Route Permission Error

### Error Message
```
one or more objects failed to apply, reason: Route.route.openshift.io "keycloak" is invalid:
spec.host: Forbidden: you do not have permission to set the host field of the route
```

### Cause
ArgoCD's service account doesn't have permission to set custom hostnames on OpenShift Routes.

### Solution

**1. Update RBAC with Route custom-host permissions:**

```bash
oc apply -f argocd-rbac.yaml
```

The updated `argocd-rbac.yaml` includes:
```yaml
- apiGroups:
    - route.openshift.io
  resources:
    - routes/custom-host
  verbs:
    - create
    - update
```

**2. Verify RBAC was applied:**

```bash
oc get clusterrole argocd-keycloak-manager -o yaml | grep -A5 "routes/custom-host"
```

**3. Retry the sync:**

ArgoCD will automatically retry if automated sync is enabled. Or manually trigger:

```bash
# Via ArgoCD UI - click "Sync" button

# Via CLI
oc patch application keycloak-instance -n openshift-gitops \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

---

## Sync Timeout Error

### Error Message
```
application controller sync timeout
```

### Cause
ArgoCD is timing out while waiting for resources to be created. This can happen with:
- Operator installations (waiting for CSV to be ready)
- StatefulSets (PostgreSQL waiting for PVC)
- Keycloak instance (waiting for database)

### Solution

**1. Check what's actually happening:**

```bash
# Check ArgoCD application status
oc get application keycloak-operator -n openshift-gitops -o yaml

# Check resources in keycloak namespace
oc get all -n keycloak

# Check events
oc get events -n keycloak --sort-by='.lastTimestamp'
```

**2. Common causes and fixes:**

#### Operator Not Installing
```bash
# Check subscription
oc get subscription rhbk-operator -n keycloak

# Check install plan
oc get installplan -n keycloak

# If manual approval needed
oc patch installplan <name> -n keycloak --type merge -p '{"spec":{"approved":true}}'
```

#### PostgreSQL PVC Not Binding
```bash
# Check PVC status
oc get pvc -n keycloak

# Check storage class
oc get storageclass

# If no default storage class, set one
oc patch storageclass <name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

#### Keycloak Pod Not Starting
```bash
# Check pod status
oc get pods -n keycloak

# Check pod logs
oc logs -n keycloak -l app=keycloak

# Describe pod for events
oc describe pod -n keycloak -l app=keycloak
```

**3. Increase sync timeout (if needed):**

The apps are configured with:
```yaml
retry:
  limit: 10
  backoff:
    duration: 10s
    factor: 2
    maxDuration: 5m
```

This gives up to 5 minutes for resources to become ready.

**4. Use sync waves for dependencies:**

Resources are already configured with sync waves:
- Wave 0: Namespace, OperatorGroup, CatalogSource
- Wave 1: Subscription, RBAC
- Wave 2: InstallPlan approver job

This ensures proper ordering.

---

## Permission Denied Errors

### Error Messages
```
deployments.apps is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource "deployments"
secrets is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource "secrets"
services is forbidden: User "system:serviceaccount:openshift-gitops:..." cannot create resource "services"
```

### Solution

Apply the RBAC configuration:

```bash
oc apply -f argocd-rbac.yaml
```

Verify:
```bash
oc get clusterrolebinding argocd-keycloak-manager
oc describe clusterrolebinding argocd-keycloak-manager
```

---

## Git Path Not Found

### Error Message
```
path 'argocd/charts/keycloak-operator' not found in repository
```

### Cause
ArgoCD Application manifests have incorrect Git paths.

### Solution

All paths should use `keycloak/` prefix (not `argocd/`):

**Infrastructure:**
- `keycloak/infra/charts/keycloak-operator`
- `keycloak/infra/charts/keycloak-instance`
- etc.

**Tenant:**
- `keycloak/tenant/charts/keycloak-users`
- `keycloak/tenant/charts/tenant-namespaces`
- etc.

**Parent apps:**
- `keycloak/infra/apps`
- `keycloak/tenant/apps`

Verify with:
```bash
grep "path:" infra/apps/*.yaml tenant/apps/*.yaml
```

All paths should start with `keycloak/`.

---

## Keycloak Instance Not Ready

### Error Message
```
Keycloak.k8s.keycloak.org "keycloak" is not ready
```

### Troubleshooting Steps

**1. Check Keycloak CR status:**
```bash
oc get keycloak keycloak -n keycloak -o yaml
```

**2. Check pods:**
```bash
oc get pods -n keycloak -l app=keycloak
```

**3. Check PostgreSQL:**
```bash
# PostgreSQL must be running first
oc get statefulset keycloak-postgresql -n keycloak
oc get pods -n keycloak -l app=keycloak-postgresql
```

**4. Check database connection:**
```bash
# View Keycloak pod logs
oc logs -n keycloak -l app=keycloak --tail=100

# Look for database connection errors
oc logs -n keycloak -l app=keycloak | grep -i "database\|postgres\|connection"
```

**5. Common issues:**

- **PostgreSQL not ready:** Wait for PostgreSQL StatefulSet to be ready
- **Database credentials wrong:** Check secret `keycloak-db-secret`
- **Resource limits:** Check if pod is being OOMKilled
- **Image pull errors:** Check ImagePullBackOff events

---

## OAuth Integration Not Working

### Symptoms
- Can't log in to OpenShift with Keycloak users
- OAuth pod errors
- Identity provider not showing in OpenShift login

### Troubleshooting

**1. Check OAuth client in Keycloak:**
```bash
# Get Keycloak admin credentials
oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d
oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d

# Login to Keycloak console
# https://sso.<your-domain>

# Verify client "idp-4-ocp" exists in realm "sso"
```

**2. Check OpenShift OAuth configuration:**
```bash
oc get oauth cluster -o yaml
```

Should include:
```yaml
spec:
  identityProviders:
  - name: keycloak
    type: OpenID
    mappingMethod: claim
    openID:
      clientID: idp-4-ocp
      # ...
```

**3. Check OAuth client secret:**
```bash
oc get secret keycloak-client-secret -n openshift-config
```

**4. Test OAuth flow manually:**
```bash
# Get OAuth endpoint
oc get route oauth-openshift -n openshift-authentication

# Try logging in via web browser
# Should redirect to Keycloak for authentication
```

---

## InstallPlan Not Approved

### Symptoms
- Operator stuck in "Installing" state
- InstallPlan exists but not approved

### Solution

**If using manual approval mode:**

```bash
# List InstallPlans
oc get installplan -n keycloak

# Approve manually
oc patch installplan <name> -n keycloak \
  --type merge -p '{"spec":{"approved":true}}'
```

**If using InstallPlan approver job:**

```bash
# Check job status
oc get job rhbk-operator-installplan-approver -n keycloak

# View job logs
oc logs job/rhbk-operator-installplan-approver -n keycloak

# If job failed, check for CSV mismatch
# Job will fail if enforceCSVMatch=true and CSV doesn't match startingCSV
```

**Change to automatic approval:**

Edit `infra/charts/keycloak-operator/values.yaml`:
```yaml
operator:
  installPlanApproval: Automatic
  installPlanApprover:
    enabled: false
```

---

## ArgoCD Application Stuck in Progressing

### Symptoms
- Application shows "Progressing" for a long time
- Sync never completes

### Troubleshooting

**1. Check application health:**
```bash
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.health.status}'
```

**2. Check sync status:**
```bash
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.sync.status}'
```

**3. View detailed status:**
```bash
oc describe application <app-name> -n openshift-gitops
```

**4. Check resource conditions:**
```bash
# See which resources are unhealthy
oc get application <app-name> -n openshift-gitops -o json | \
  jq '.status.resources[] | select(.health.status != "Healthy")'
```

**5. Force refresh:**
```bash
# Delete and recreate the application
oc delete application <app-name> -n openshift-gitops
oc apply -f <app-file.yaml>
```

---

## General Debugging Commands

### ArgoCD Application Status
```bash
# List all applications
oc get applications -n openshift-gitops

# Get specific app details
oc describe application keycloak-operator -n openshift-gitops

# View app as YAML
oc get application keycloak-operator -n openshift-gitops -o yaml

# Watch for changes
watch oc get applications -n openshift-gitops
```

### Resource Status
```bash
# All resources in keycloak namespace
oc get all -n keycloak

# Keycloak CRs
oc get keycloak,keycloakrealmimport,keycloakuser -n keycloak

# Events (sorted by time)
oc get events -n keycloak --sort-by='.lastTimestamp'

# Operator resources
oc get subscription,operatorgroup,catalogsource -n keycloak
```

### Logs
```bash
# Keycloak operator logs
oc logs -n keycloak -l app.kubernetes.io/name=rhbk-operator

# Keycloak instance logs
oc logs -n keycloak -l app=keycloak

# PostgreSQL logs
oc logs -n keycloak -l app=keycloak-postgresql

# ArgoCD application controller logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller
```

---

## Getting Help

If you're still stuck:

1. **Check application status:**
   ```bash
   oc get application -n openshift-gitops -o yaml > app-status.yaml
   ```

2. **Collect resource status:**
   ```bash
   oc get all,keycloak,keycloakrealmimport,keycloakuser -n keycloak -o yaml > resources.yaml
   ```

3. **Collect events:**
   ```bash
   oc get events -n keycloak --sort-by='.lastTimestamp' > events.txt
   ```

4. **Share the above files** with your team or in support channels.
