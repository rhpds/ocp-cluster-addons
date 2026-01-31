# GUID-Based Multi-Tenancy Architecture

This ArgoCD deployment supports **GUID-based multi-tenancy**, allowing multiple isolated tenant environments to coexist on the same OpenShift cluster.

## Directory Structure

```
argocd/
├── infra/                          # Infrastructure components (shared)
│   ├── apps/                       # ArgoCD Application manifests
│   │   ├── keycloak-operator.yaml
│   │   ├── keycloak-postgres.yaml
│   │   ├── keycloak-instance.yaml
│   │   ├── keycloak-realm.yaml
│   │   └── keycloak-oauth.yaml
│   ├── charts/                     # Helm charts
│   │   ├── keycloak-operator/     # RHBK Operator
│   │   ├── keycloak-postgres/     # PostgreSQL database
│   │   ├── keycloak-instance/     # Keycloak instance
│   │   ├── keycloak-realm/        # Realm + admin user
│   │   └── keycloak-oauth/        # OpenShift OAuth integration
│   └── parent-app.yaml            # Infrastructure parent app
│
├── tenant/                         # Tenant-specific resources
│   ├── apps/                       # ArgoCD Application manifests
│   │   ├── keycloak-users.yaml
│   │   ├── tenant-namespaces.yaml
│   │   └── tenant-rbac.yaml
│   ├── charts/                     # Helm charts
│   │   ├── keycloak-users/        # Tenant Keycloak users
│   │   ├── tenant-namespaces/     # Tenant namespaces
│   │   └── tenant-rbac/           # Tenant RBAC
│   ├── examples/                   # Example configurations
│   │   ├── team-a-values.yaml
│   │   ├── workshop-values.yaml
│   │   ├── multi-env-values.yaml
│   │   └── applicationset-multi-tenant.yaml
│   ├── parent-app.yaml            # Tenant parent app
│   └── README.md                   # Tenant documentation
│
└── platform-parent-app.yaml       # Master parent (infra + tenant)
```

## Component Separation

### Infrastructure (infra/)

**Purpose:** Deploy and configure the Keycloak platform (one-time setup per cluster)

**Components:**
- **keycloak-operator**: Installs RHBK operator via OLM
- **keycloak-postgres**: PostgreSQL database for Keycloak
- **keycloak-instance**: Keycloak server instance
- **keycloak-realm**: Creates realm structure, roles, groups, admin user
- **keycloak-oauth**: Integrates Keycloak with OpenShift OAuth

**Scope:** Cluster-wide, shared infrastructure

**Deploy once per cluster**

### Tenant (tenant/)

**Purpose:** Deploy tenant-specific resources (can be deployed multiple times with different GUIDs)

**Components:**
- **keycloak-users**: Creates Keycloak users with GUID-based naming
- **tenant-namespaces**: Creates OpenShift namespaces with quotas/limits
- **tenant-rbac**: Creates RoleBindings for user access

**Scope:** Per-tenant, isolated by GUID

**Deploy once per tenant (team, workshop, project, etc.)**

## GUID-Based Naming

All tenant resources use a GUID for uniqueness:

| Component | Without GUID | With GUID `team-a` | With GUID `team-b` |
|-----------|--------------|--------------------|--------------------|
| Username | `user1` | `user1-team-a` | `user1-team-b` |
| Namespace | `user1-project` | `user1-team-a-project` | `user1-team-b-project` |
| RoleBinding | `user1-admin` | `user1-team-a-admin` | `user1-team-b-admin` |

This allows multiple tenants to coexist without naming conflicts.

## Quick Start

### Step 1: Deploy Infrastructure (Once)

```bash
# Deploy the infrastructure components
oc apply -f argocd/infra/parent-app.yaml

# Wait for infrastructure to be ready
oc wait --for=condition=Ready keycloak/keycloak -n keycloak --timeout=600s
```

### Step 2: Deploy Tenant (Multiple Times)

**Option A: Single tenant using values file**

```bash
# Create tenant values file
cat > tenant/my-team-values.yaml <<EOF
tenant:
  guid: "my-team"

users:
  mode: generate
  generate:
    count: 5
    prefix: developer
  password: "SecurePass123!"

namespaces:
  mode: generate
  generate:
    count: 5
    prefix: my-team-dev
    suffix: -workspace

rbac:
  namespaceAdmin:
    enabled: true
    clusterRole: admin
EOF

# Deploy tenant charts with values
helm install my-team-users tenant/charts/keycloak-users -f tenant/my-team-values.yaml -n keycloak
helm install my-team-namespaces tenant/charts/tenant-namespaces -f tenant/my-team-values.yaml
helm install my-team-rbac tenant/charts/tenant-rbac -f tenant/my-team-values.yaml
```

**Option B: Multiple tenants using ApplicationSet**

```bash
# Deploy the multi-tenant ApplicationSet
oc apply -f tenant/examples/applicationset-multi-tenant.yaml

# This creates:
# - team-red with 5 users
# - team-blue with 3 users
# - team-green with 10 users
```

**Option C: Deploy all (infrastructure + tenant)**

```bash
# Deploy everything at once
oc apply -f argocd/platform-parent-app.yaml
```

## Usage Examples

### Example 1: Development Team

**Scenario:** Create a development team with 5 developers

```yaml
tenant:
  guid: "dev-team-alpha"

users:
  mode: generate
  generate:
    count: 5
    prefix: developer

namespaces:
  mode: generate
  generate:
    count: 5
    prefix: dev
    suffix: -workspace
```

**Creates:**
- Users: `developer1-dev-team-alpha` ... `developer5-dev-team-alpha`
- Namespaces: `dev1-dev-team-alpha-workspace` ... `dev5-dev-team-alpha-workspace`

### Example 2: Workshop/Training

**Scenario:** Create 50 student accounts for a workshop

```yaml
tenant:
  guid: "workshop-2026-01"

users:
  mode: generate
  generate:
    count: 50
    prefix: student

namespaces:
  mode: generate
  generate:
    count: 50
    prefix: student
    suffix: -lab
```

**Creates:**
- Users: `student1-workshop-2026-01` ... `student50-workshop-2026-01`
- Namespaces: `student1-workshop-2026-01-lab` ... `student50-workshop-2026-01-lab`

### Example 3: Multi-Environment Project

**Scenario:** Named users with dev/staging/prod environments

```yaml
tenant:
  guid: "product-alpha"

users:
  mode: explicit
  explicit:
    usernames: [alice, bob, charlie]

namespaces:
  mode: explicit
  explicit:
    names: [dev, staging, prod]
```

**Creates:**
- Users: `alice-product-alpha`, `bob-product-alpha`, `charlie-product-alpha`
- Namespaces: `dev-product-alpha`, `staging-product-alpha`, `prod-product-alpha`

## Deployment Workflows

### Workflow 1: GitOps (Recommended)

1. Commit tenant values to Git
2. Create ArgoCD Application pointing to tenant charts
3. ArgoCD syncs and deploys resources
4. Updates tracked in Git history

### Workflow 2: Direct Helm

1. Create tenant values file
2. Deploy with `helm install` commands
3. Manual management of resources

### Workflow 3: ApplicationSet

1. Define tenants in ApplicationSet generator
2. Deploy ApplicationSet
3. ArgoCD creates Application per tenant
4. Centralized multi-tenant management

## Multi-Tenant Scenarios

### Scenario: Multiple Teams on One Cluster

```bash
# Deploy infrastructure once
oc apply -f infra/parent-app.yaml

# Deploy team-a tenant
helm install team-a-users tenant/charts/keycloak-users -f team-a-values.yaml -n keycloak
helm install team-a-namespaces tenant/charts/tenant-namespaces -f team-a-values.yaml
helm install team-a-rbac tenant/charts/tenant-rbac -f team-a-values.yaml

# Deploy team-b tenant
helm install team-b-users tenant/charts/keycloak-users -f team-b-values.yaml -n keycloak
helm install team-b-namespaces tenant/charts/tenant-namespaces -f team-b-values.yaml
helm install team-b-rbac tenant/charts/tenant-rbac -f team-b-values.yaml

# Both teams coexist with no conflicts
```

### Scenario: Ephemeral Workshop Environments

```bash
# Create workshop environment for session-123
export GUID="workshop-session-123"
helm install $GUID-users tenant/charts/keycloak-users \
  --set tenant.guid=$GUID \
  --set users.generate.count=30 \
  -n keycloak

# Workshop ends - cleanup
helm uninstall $GUID-users -n keycloak
oc delete namespace -l tenant-guid=$GUID
```

## Benefits of GUID-Based Multi-Tenancy

1. **No Naming Conflicts**: Multiple tenants coexist safely
2. **Easy Cleanup**: Delete all tenant resources by GUID label
3. **Clear Ownership**: Label shows which tenant owns each resource
4. **Scalable**: Support unlimited tenants on one cluster
5. **Flexible**: Mix different user/namespace configurations
6. **Traceable**: GUID in all resource names for easy identification

## Configuration Reference

See detailed configuration in:
- Infrastructure: `infra/charts/*/values.yaml`
- Tenant: `tenant/charts/*/values.yaml`
- Examples: `tenant/examples/*.yaml`

## Verification

```bash
# List all tenants
oc get keycloakuser -n keycloak -o jsonpath='{range .items[*]}{.metadata.labels.tenant-guid}{"\n"}{end}' | sort -u

# List resources for specific tenant
export GUID="team-a"
oc get keycloakuser -n keycloak -l tenant-guid=$GUID
oc get namespace -l tenant-guid=$GUID
oc get rolebinding -A -l tenant-guid=$GUID

# Test user login
oc login --username=user1-$GUID --password=<password>
```

## Cleanup

```bash
# Remove specific tenant
export GUID="team-a"
oc delete keycloakuser -n keycloak -l tenant-guid=$GUID
oc delete namespace -l tenant-guid=$GUID
oc delete rolebinding -A -l tenant-guid=$GUID

# Remove all tenants (keep infrastructure)
oc delete keycloakuser -n keycloak -l app.kubernetes.io/component=tenant
oc delete namespace -l app.kubernetes.io/component=tenant

# Remove everything
oc delete application keycloak-platform -n openshift-gitops
```

## Documentation

- **Infrastructure README**: `README.md` (main documentation)
- **Tenant README**: `tenant/README.md` (GUID and multi-tenancy)
- **Quick Start**: `QUICKSTART.md`
- **Conversion Summary**: `CONVERSION_SUMMARY.md`
- **Sync Waves**: `sync-waves.md`

## Examples

See `tenant/examples/` for complete working examples:
- `team-a-values.yaml` - Development team
- `workshop-values.yaml` - Workshop with 50 students
- `multi-env-values.yaml` - Multi-environment project
- `applicationset-multi-tenant.yaml` - Multi-tenant ApplicationSet

## Support

For issues or questions:
1. Check tenant README: `tenant/README.md`
2. Review examples: `tenant/examples/`
3. Verify GUID consistency across all three charts
4. Check ArgoCD application status
5. Review Keycloak operator logs
