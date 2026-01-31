# ArgoCD Sync Waves and Dependencies

This document explains the deployment order and sync wave strategy for the Keycloak platform.

## Sync Wave Strategy

The applications are deployed in a specific order using ArgoCD's sync wave mechanism. Each wave waits for the previous wave to be healthy before proceeding.

### Wave 0: Operator Installation
**Application**: `keycloak-operator`

- Creates namespace
- Installs OperatorGroup
- Creates Subscription for RHBK operator
- Waits for operator CSV to be in "Succeeded" phase

**Dependencies**: None

**Health Check**: Operator pod running and CSV succeeded

---

### Wave 1: Database Layer
**Application**: `keycloak-postgres`

- Creates PostgreSQL secret with credentials
- Creates PVC for database storage
- Deploys PostgreSQL pod
- Creates PostgreSQL service

**Dependencies**:
- Namespace created by Wave 0
- No dependency on operator being ready

**Health Check**: PostgreSQL pod ready

---

### Wave 2: Keycloak Instance
**Application**: `keycloak-instance`

- Creates service-serving certificate service
- Deploys Keycloak custom resource
- Creates OpenShift route

**Dependencies**:
- Operator from Wave 0 must be ready
- PostgreSQL from Wave 1 must be running
- Database secret from Wave 1 must exist

**Health Check**:
- Keycloak CR status is Ready
- Keycloak pods are running
- Route is accessible

---

### Wave 3: Realm Configuration
**Application**: `keycloak-realm`

- Creates KeycloakRealmImport custom resource
- Imports realm configuration
- Creates users (admin and regular users)
- Creates OpenID client for OpenShift

**Dependencies**:
- Keycloak instance from Wave 2 must be ready
- Keycloak must be accessible

**Health Check**:
- KeycloakRealmImport status is Done
- Users are created in Keycloak

---

### Wave 4: OAuth Integration
**Application**: `keycloak-oauth`

- Creates OAuth client secret in openshift-config namespace
- Patches cluster OAuth configuration
- Creates ClusterRoleBinding for admin user
- Optionally removes kubeadmin user

**Dependencies**:
- Realm from Wave 3 must be imported
- OpenID client must exist in Keycloak
- Keycloak route must be accessible

**Health Check**:
- OAuth config is updated
- Authentication pods restart and become ready
- Can login with Keycloak users

---

## Implementation

### Current Implementation

Currently, sync waves are implemented through application retry logic and health checks:

1. Each Application has retry configuration with backoff
2. Applications won't be healthy until their dependencies are met
3. ArgoCD automatically manages the sync order based on health status

### Alternative: Explicit Sync Waves

To implement explicit sync waves, add annotations to each Application:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Wave number
```

### Recommended Sync Wave Annotations

If you want to add explicit sync waves to the Applications:

**keycloak-operator.yaml**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

**keycloak-postgres.yaml**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

**keycloak-instance.yaml**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

**keycloak-realm.yaml**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

**keycloak-oauth.yaml**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "4"
```

## Resource-Level Sync Waves

Within each Helm chart, you can also add sync waves to individual resources:

### Example: keycloak-operator chart

```yaml
# Namespace first
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

# Then OperatorGroup
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Finally Subscription
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

### Example: keycloak-postgres chart

```yaml
# Secret first
apiVersion: v1
kind: Secret
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Then PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Then Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"

# Finally Service
apiVersion: v1
kind: Service
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

## Health Checks

ArgoCD uses these health checks to determine when to proceed to the next wave:

### Operator Health
```bash
oc get csv -n keycloak -l operators.coreos.com/rhbk-operator.keycloak='' -o jsonpath='{.items[0].status.phase}'
# Should return: Succeeded
```

### PostgreSQL Health
```bash
oc get pods -n keycloak -l app=keycloak-pgsql -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'
# Should return: True
```

### Keycloak Instance Health
```bash
oc get keycloak keycloak -n keycloak -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Should return: True
```

### Realm Import Health
```bash
oc get keycloakrealmimport sso -n keycloak -o jsonpath='{.status.conditions[?(@.type=="Done")].status}'
# Should return: True
```

### OAuth Health
```bash
oc get pods -n openshift-authentication -l app=oauth-openshift -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
# Should return: True True True (for all replicas)
```

## Troubleshooting Wave Failures

### Wave 0 Failure (Operator)
```bash
# Check subscription
oc get subscription rhbk-operator -n keycloak -o yaml

# Check install plan
oc get installplan -n keycloak

# Manually approve if needed
oc patch installplan <install-plan-name> -n keycloak --type merge -p '{"spec":{"approved":true}}'
```

### Wave 1 Failure (PostgreSQL)
```bash
# Check PVC binding
oc get pvc -n keycloak

# Check pod events
oc describe pod -l app=keycloak-pgsql -n keycloak

# Check logs
oc logs -l app=keycloak-pgsql -n keycloak
```

### Wave 2 Failure (Keycloak Instance)
```bash
# Check Keycloak CR status
oc get keycloak keycloak -n keycloak -o yaml

# Check operator logs
oc logs -n keycloak -l app.kubernetes.io/managed-by=keycloak-operator

# Check Keycloak pod logs
oc logs keycloak-0 -n keycloak
```

### Wave 3 Failure (Realm Import)
```bash
# Check realm import status
oc get keycloakrealmimport sso -n keycloak -o yaml

# Check operator logs
oc logs -n keycloak -l app.kubernetes.io/managed-by=keycloak-operator --tail=100
```

### Wave 4 Failure (OAuth)
```bash
# Check OAuth config
oc get oauth cluster -o yaml

# Check authentication operator logs
oc logs -n openshift-authentication-operator deployment/authentication-operator

# Check OAuth pods
oc get pods -n openshift-authentication
oc logs -n openshift-authentication -l app=oauth-openshift
```

## Manual Wave Progression

If automatic progression fails, you can manually sync waves:

```bash
# Sync specific wave
argocd app sync keycloak-operator --force
argocd app sync keycloak-postgres --force
argocd app sync keycloak-instance --force
argocd app sync keycloak-realm --force
argocd app sync keycloak-oauth --force

# Or sync all at once (not recommended for first deployment)
argocd app sync -l app.kubernetes.io/instance=keycloak-platform
```
