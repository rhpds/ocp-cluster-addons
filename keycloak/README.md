# Keycloak on OpenShift - ArgoCD Applications

This directory contains ArgoCD applications and Helm charts to deploy Red Hat Build of Keycloak (RHBK) on OpenShift with OAuth integration.

## Architecture

This deployment uses the **App of Apps** pattern with the following structure:

```
argocd/
├── parent-app.yaml                 # Parent Application (App of Apps)
├── apps/                           # Child Application manifests
│   ├── keycloak-operator.yaml
│   ├── keycloak-postgres.yaml
│   ├── keycloak-instance.yaml
│   ├── keycloak-realm.yaml
│   └── keycloak-oauth.yaml
└── charts/                         # Helm charts
    ├── keycloak-operator/          # RHBK Operator installation
    ├── keycloak-postgres/          # PostgreSQL database
    ├── keycloak-instance/          # Keycloak instance
    ├── keycloak-realm/             # Realm and users configuration
    └── keycloak-oauth/             # OpenShift OAuth integration
```

## Components

### 1. keycloak-operator
- Installs the Red Hat Build of Keycloak operator via OLM
- Creates namespace, OperatorGroup, and Subscription
- Optional: Custom CatalogSource for disconnected environments

### 2. keycloak-postgres
- Deploys PostgreSQL 16 as the Keycloak database
- Includes PVC for persistent storage
- Creates database secret with credentials

### 3. keycloak-instance
- Deploys the Keycloak instance using the operator
- Creates OpenShift Route for external access
- Configures TLS with service-serving certificates

### 4. keycloak-realm
- Creates a Keycloak realm with configurable users
- Supports admin user with cluster-admin role
- Supports multiple regular users
- Configures OpenID Connect client for OpenShift

### 5. keycloak-oauth
- Configures OpenShift OAuth to use Keycloak as identity provider
- Creates ClusterRoleBinding for admin user
- Optional: Removes kubeadmin user after OAuth is working

## Prerequisites

1. OpenShift cluster (4.12+)
2. OpenShift GitOps operator installed
3. Git repository to host these manifests
4. Cluster admin access

## Configuration

### Required Configuration Changes

Before deploying, you MUST update the following values:

#### 1. Git Repository URLs
Update in all files under `argocd/apps/`:
```yaml
repoURL: https://github.com/YOUR-ORG/YOUR-REPO.git  # Change this
targetRevision: main  # Or your branch name
```

#### 2. OpenShift Ingress Domain
Update in the following chart values files:

**argocd/charts/keycloak-instance/values.yaml**:
```yaml
keycloak:
  ingressDomain: apps.example.com  # Change to your cluster's ingress domain
```

**argocd/charts/keycloak-oauth/values.yaml**:
```yaml
oauth:
  ingressDomain: apps.example.com  # Must match keycloak-instance
```

To get your cluster's ingress domain:
```bash
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
```

#### 3. Passwords and Secrets

**CRITICAL**: Change default passwords before production use!

Update these files:

**argocd/charts/keycloak-postgres/values.yaml**:
```yaml
postgresql:
  database:
    password: changeme123  # Change this!
```

**argocd/charts/keycloak-realm/values.yaml**:
```yaml
realm:
  client:
    secret: changeme123  # Change this!
  users:
    admin:
      password: changeme123  # Change this!
    regular:
      password: changeme123  # Change this!
```

**argocd/charts/keycloak-oauth/values.yaml**:
```yaml
oauth:
  client:
    secret: changeme123  # Must match realm.client.secret above!
```

### Optional Configuration

#### Number of Users
**argocd/charts/keycloak-realm/values.yaml**:
```yaml
realm:
  users:
    regular:
      count: 5  # Number of regular users to create (user1, user2, etc.)
```

#### Disable Admin User
**argocd/charts/keycloak-realm/values.yaml**:
```yaml
realm:
  users:
    admin:
      enabled: false  # Disable admin user creation
```

#### Remove Kubeadmin User
**WARNING**: Only enable this after confirming OAuth works!

**argocd/charts/keycloak-oauth/values.yaml**:
```yaml
rbac:
  removeKubeadmin:
    enabled: true  # Enable to remove kubeadmin user
```

#### Custom Catalog Source
For disconnected environments:

**argocd/charts/keycloak-operator/values.yaml**:
```yaml
operator:
  catalogSource:
    enabled: true
    name: custom-redhat-catalog
    image: quay.io/gpte-devops-automation/olm_snapshot_redhat_catalog
    tag: v4.20_2025_10_23
```

## Deployment Instructions

### Option 1: Deploy Parent App (Recommended)

1. Update configuration as described above
2. Commit and push changes to your Git repository
3. Deploy the parent application:

```bash
oc apply -f argocd/parent-app.yaml
```

This will automatically deploy all child applications in the correct order.

### Option 2: Deploy Individual Apps

Deploy applications in this order:

```bash
# 1. Deploy operator
oc apply -f argocd/apps/keycloak-operator.yaml

# Wait for operator to be ready
oc wait --for=condition=Ready pod -l name=rhbk-operator -n keycloak --timeout=300s

# 2. Deploy PostgreSQL
oc apply -f argocd/apps/keycloak-postgres.yaml

# Wait for PostgreSQL to be ready
oc wait --for=condition=Ready pod -l app=keycloak-pgsql -n keycloak --timeout=300s

# 3. Deploy Keycloak instance
oc apply -f argocd/apps/keycloak-instance.yaml

# Wait for Keycloak to be ready
oc wait --for=condition=Ready keycloak/keycloak -n keycloak --timeout=600s

# 4. Deploy realm configuration
oc apply -f argocd/apps/keycloak-realm.yaml

# Wait for realm import to complete
oc wait --for=condition=Done keycloakrealmimport/sso -n keycloak --timeout=300s

# 5. Deploy OAuth integration
oc apply -f argocd/apps/keycloak-oauth.yaml
```

## Accessing Keycloak

After deployment:

1. Get the Keycloak admin credentials:
```bash
KC_USER=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)
KC_PASS=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)
echo "Admin User: $KC_USER"
echo "Admin Password: $KC_PASS"
```

2. Get the Keycloak console URL:
```bash
oc get route keycloak -n keycloak -o jsonpath='{.spec.host}'
```

3. Access OpenShift console with Keycloak users:
   - Admin user: `admin` / (password from values.yaml)
   - Regular users: `user1`, `user2`, etc. / (password from values.yaml)

## Verification

### Verify Operator Installation
```bash
oc get csv -n keycloak | grep rhbk-operator
oc get pods -n keycloak | grep rhbk-operator
```

### Verify PostgreSQL
```bash
oc get pods -n keycloak | grep keycloak-pgsql
oc get pvc -n keycloak
```

### Verify Keycloak Instance
```bash
oc get keycloak -n keycloak
oc get pods -n keycloak | grep keycloak-0
oc get route -n keycloak
```

### Verify Realm Configuration
```bash
oc get keycloakrealmimport -n keycloak
```

### Verify OAuth Integration
```bash
oc get oauth cluster -o yaml
oc get secret openid-client-secret-bb6zw -n openshift-config
```

### Test OAuth Login
```bash
# Get OpenShift console URL
oc whoami --show-console

# Login with Keycloak user
oc login --username=user1 --password=<password>
```

## Troubleshooting

### Operator Not Installing
```bash
# Check subscription status
oc get subscription rhbk-operator -n keycloak -o yaml

# Check install plan
oc get installplan -n keycloak

# Check operator pod logs
oc logs -n keycloak -l name=rhbk-operator
```

### Keycloak Not Starting
```bash
# Check Keycloak CR status
oc get keycloak keycloak -n keycloak -o yaml

# Check Keycloak pod logs
oc logs -n keycloak keycloak-0

# Check PostgreSQL connectivity
oc exec -n keycloak keycloak-0 -- curl -v keycloak-pgsql:5432
```

### Realm Import Failing
```bash
# Check realm import status
oc get keycloakrealmimport sso -n keycloak -o yaml

# Check Keycloak operator logs
oc logs -n keycloak -l app.kubernetes.io/managed-by=keycloak-operator
```

### OAuth Not Working
```bash
# Check OAuth config
oc get oauth cluster -o yaml

# Check OAuth pods
oc get pods -n openshift-authentication

# Check OAuth pod logs
oc logs -n openshift-authentication -l app=oauth-openshift
```

### ArgoCD Sync Issues
```bash
# Check application status
oc get application -n openshift-gitops

# Check specific application
oc describe application keycloak-instance -n openshift-gitops

# Force sync
argocd app sync keycloak-instance --force
```

## Security Considerations

1. **Change Default Passwords**: All default passwords MUST be changed before production use
2. **Secret Management**: Consider using:
   - Sealed Secrets
   - External Secrets Operator
   - Vault integration
3. **OAuth Secret**: The client secret must match between realm and OAuth configuration
4. **PostgreSQL Password**: Stored in a Kubernetes secret
5. **Kubeadmin Removal**: Only enable after confirming OAuth authentication works

## Uninstallation

To remove all components:

```bash
# Delete parent app (will delete all child apps)
oc delete application keycloak-platform -n openshift-gitops

# Or delete individual apps
oc delete application keycloak-oauth -n openshift-gitops
oc delete application keycloak-realm -n openshift-gitops
oc delete application keycloak-instance -n openshift-gitops
oc delete application keycloak-postgres -n openshift-gitops
oc delete application keycloak-operator -n openshift-gitops

# Clean up OAuth configuration
oc patch oauth cluster --type=json -p='[{"op": "remove", "path": "/spec/identityProviders"}]'

# Delete namespace (optional)
oc delete namespace keycloak
```

## Migration from Ansible Role

This ArgoCD setup replaces the Ansible role with the following mappings:

| Ansible Role | ArgoCD Component |
|--------------|------------------|
| `install_operator` role | `keycloak-operator` chart |
| PostgreSQL templates | `keycloak-postgres` chart |
| Keycloak instance templates | `keycloak-instance` chart |
| Realm import template | `keycloak-realm` chart |
| OAuth templates | `keycloak-oauth` chart |

Default values from `defaults/main.yml` are now in each chart's `values.yaml` file.

## References

- [Red Hat build of Keycloak Operator Documentation](https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak)
- [OpenShift OAuth Configuration](https://docs.openshift.com/container-platform/latest/authentication/understanding-identity-provider.html)
- [ArgoCD App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
