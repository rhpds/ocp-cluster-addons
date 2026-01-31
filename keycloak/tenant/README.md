# Keycloak Tenant Resources

This directory contains Helm charts for deploying tenant-specific resources including Keycloak users, namespaces, and RBAC configurations.

## GUID-Based Multi-Tenancy

All tenant resources use a **GUID (Global Unique Identifier)** to enable multiple tenant deployments on the same cluster without conflicts. The GUID is appended to all resource names.

### How It Works

**Example with GUID `team-a`:**

| Resource Type | Generated Name | Pattern |
|---------------|----------------|---------|
| Keycloak Users | `user1-team-a`, `user2-team-a` | `{prefix}{num}-{guid}` |
| Namespaces | `user1-team-a-project`, `user2-team-a-project` | `{prefix}{num}-{guid}{suffix}` |
| RoleBindings | Created in each namespace | Maps user to namespace |

This allows multiple tenants to coexist:
- Team A: `user1-team-a`, `user1-team-a-project`
- Team B: `user1-team-b`, `user1-team-b-project`

## Charts

### 1. keycloak-users
Creates Keycloak users in the realm with GUID-based naming.

**Features:**
- Generate users from count (e.g., `user1-guid`, `user2-guid`)
- Explicit user list (e.g., `john-guid`, `jane-guid`)
- Configurable passwords, roles, and attributes

### 2. tenant-namespaces
Creates OpenShift/Kubernetes namespaces for tenants with resource quotas and limit ranges.

**Features:**
- Generate namespaces from count
- Explicit namespace list
- ResourceQuota configuration
- LimitRange configuration
- NetworkPolicy support (optional)

### 3. tenant-rbac
Creates RoleBindings to grant users access to their namespaces.

**Features:**
- Auto-map users to their respective namespaces
- Shared namespace access (optional)
- Custom RoleBindings (optional)
- Group-based RBAC (optional)

## User Creation Modes

Both **generate** and **explicit** modes are supported:

### Generate Mode (Default)
Users are created from a count + prefix + GUID:

```yaml
tenant:
  guid: "team-a"

users:
  mode: generate
  generate:
    count: 3
    prefix: user
    startNumber: 1
```

**Creates:**
- `user1-team-a`
- `user2-team-a`
- `user3-team-a`

### Explicit Mode
Provide specific usernames:

```yaml
tenant:
  guid: "team-a"

users:
  mode: explicit
  explicit:
    usernames:
      - john
      - jane
      - bob
```

**Creates:**
- `john-team-a`
- `jane-team-a`
- `bob-team-a`

## Quick Start

### 1. Create Tenant-Specific Values File

Create `tenant/my-values-team-a.yaml`:

```yaml
# All three charts must use the same GUID
tenant:
  guid: "team-a"

# Keycloak users configuration
users:
  mode: generate
  generate:
    count: 5
    prefix: user
  password: "SecurePassword123!"

# Namespaces configuration
namespaces:
  mode: generate
  generate:
    count: 5
    prefix: user
    suffix: -project

# RBAC configuration
rbac:
  namespaceAdmin:
    enabled: true
    clusterRole: admin
```

### 2. Deploy Tenant Applications

**Option A: Deploy all tenant apps together:**

```bash
# Update the Application manifests to use your values file
# Then deploy
oc apply -f tenant/apps/
```

**Option B: Deploy each chart individually:**

```bash
# Install keycloak-users
helm install team-a-users tenant/charts/keycloak-users \
  -f tenant/my-values-team-a.yaml \
  -n keycloak

# Install tenant-namespaces
helm install team-a-namespaces tenant/charts/tenant-namespaces \
  -f tenant/my-values-team-a.yaml

# Install tenant-rbac
helm install team-a-rbac tenant/charts/tenant-rbac \
  -f tenant/my-values-team-a.yaml
```

### 3. Verify Deployment

```bash
# Check Keycloak users
oc get keycloakuser -n keycloak -l tenant-guid=team-a

# Check namespaces
oc get namespace -l tenant-guid=team-a

# Check role bindings
oc get rolebinding -A -l tenant-guid=team-a
```

## Multi-Tenant Example

Deploy two separate tenants on the same cluster:

### Team A

**`tenant/values-team-a.yaml`:**
```yaml
tenant:
  guid: "team-a"

users:
  mode: generate
  generate:
    count: 3
    prefix: developer
  password: "TeamA-Password!"

namespaces:
  mode: generate
  generate:
    count: 3
    prefix: team-a
    suffix: -env
```

**Deploys:**
- Users: `developer1-team-a`, `developer2-team-a`, `developer3-team-a`
- Namespaces: `team-a1-team-a-env`, `team-a2-team-a-env`, `team-a3-team-a-env`

### Team B

**`tenant/values-team-b.yaml`:**
```yaml
tenant:
  guid: "team-b"

users:
  mode: explicit
  explicit:
    usernames:
      - alice
      - bob
      - charlie
  password: "TeamB-Password!"

namespaces:
  mode: explicit
  explicit:
    names:
      - dev
      - staging
      - prod
```

**Deploys:**
- Users: `alice-team-b`, `bob-team-b`, `charlie-team-b`
- Namespaces: `dev-team-b`, `staging-team-b`, `prod-team-b`

## ArgoCD Application Examples

### Tenant-Specific Application

Create `tenant/apps/team-a.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-a-tenant
  namespace: openshift-gitops
spec:
  generators:
    - list:
        elements:
          - chart: keycloak-users
          - chart: tenant-namespaces
          - chart: tenant-rbac
  template:
    metadata:
      name: team-a-{{chart}}
    spec:
      project: default
      source:
        repoURL: https://github.com/YOUR-ORG/YOUR-REPO.git
        targetRevision: main
        path: argocd/tenant/charts/{{chart}}
        helm:
          valueFiles:
            - values.yaml
          values: |
            tenant:
              guid: "team-a"
            users:
              mode: generate
              generate:
                count: 5
                prefix: user
              password: "ChangeMe123!"
            namespaces:
              mode: generate
              generate:
                count: 5
                prefix: user
                suffix: -project
      destination:
        server: https://kubernetes.default.svc
        namespace: keycloak
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Multi-Tenant ApplicationSet

Deploy multiple tenants with one ApplicationSet:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-tenant-deployment
  namespace: openshift-gitops
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - guid: team-a
                  userCount: "5"
                  userPrefix: developer
                - guid: team-b
                  userCount: "3"
                  userPrefix: user
                - guid: team-c
                  userCount: "10"
                  userPrefix: student
          - list:
              elements:
                - chart: keycloak-users
                - chart: tenant-namespaces
                - chart: tenant-rbac
  template:
    metadata:
      name: '{{guid}}-{{chart}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/YOUR-ORG/YOUR-REPO.git
        targetRevision: main
        path: argocd/tenant/charts/{{chart}}
        helm:
          valueFiles:
            - values.yaml
          values: |
            tenant:
              guid: "{{guid}}"
            users:
              mode: generate
              generate:
                count: {{userCount}}
                prefix: {{userPrefix}}
              password: "SecurePass-{{guid}}"
            namespaces:
              mode: generate
              generate:
                count: {{userCount}}
                prefix: {{userPrefix}}
                suffix: -workspace
      destination:
        server: https://kubernetes.default.svc
        namespace: keycloak
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Configuration Reference

### Required Values (All Charts)

```yaml
tenant:
  guid: "unique-identifier"  # REQUIRED - Must be unique per tenant
```

### User Configuration (keycloak-users chart)

```yaml
users:
  mode: generate  # or "explicit"

  # Generate mode
  generate:
    count: 5
    prefix: user
    startNumber: 1

  # Explicit mode
  explicit:
    usernames:
      - user1
      - user2

  # Common settings
  password: "changeme123"
  emailDomain: demo.redhat.com
  realmRoles:
    - user
```

### Namespace Configuration (tenant-namespaces chart)

```yaml
namespaces:
  mode: generate  # or "explicit"

  # Generate mode
  generate:
    count: 5
    prefix: user
    suffix: -project
    startNumber: 1

  # Explicit mode
  explicit:
    names:
      - dev
      - staging
      - prod

  labels:
    tenant: "true"

resourceQuota:
  enabled: true
  limits:
    cpu: "4"
    memory: 8Gi

limitRange:
  enabled: true
```

### RBAC Configuration (tenant-rbac chart)

```yaml
rbac:
  namespaceAdmin:
    enabled: true
    clusterRole: admin  # or edit, view

  sharedNamespaceAccess:
    enabled: false
    namespaces:
      - shared-tools
    clusterRole: view
```

## Best Practices

1. **GUID Selection:**
   - Use descriptive, meaningful GUIDs (e.g., `team-a`, `project-12345`)
   - Keep GUIDs short but unique
   - Use lowercase and hyphens only

2. **Consistency:**
   - Use the **same GUID** across all three charts (users, namespaces, rbac)
   - Use the **same mode** (generate or explicit) across all charts
   - Match user count with namespace count in generate mode

3. **Security:**
   - Change default passwords
   - Use external secret management in production
   - Apply appropriate ResourceQuotas

4. **Organization:**
   - Create separate values files per tenant
   - Use ApplicationSets for managing multiple tenants
   - Label all resources with `tenant-guid`

## Troubleshooting

### Users not created
```bash
# Check KeycloakUser resources
oc get keycloakuser -n keycloak -l tenant-guid=YOUR-GUID

# Check Keycloak operator logs
oc logs -n keycloak -l app.kubernetes.io/managed-by=keycloak-operator
```

### Namespaces not created
```bash
# Check if namespaces exist
oc get namespace -l tenant-guid=YOUR-GUID

# Check ArgoCD application
oc get application tenant-namespaces -n openshift-gitops -o yaml
```

### RoleBindings not working
```bash
# Check role bindings
oc get rolebinding -n NAMESPACE -l tenant-guid=YOUR-GUID

# Test user access
oc auth can-i get pods -n NAMESPACE --as=user1-YOUR-GUID
```

### GUID mismatch between charts
All three charts **must** use the same GUID. Check values:
```bash
# Get GUID from users
oc get keycloakuser -n keycloak -o jsonpath='{.items[0].metadata.labels.tenant-guid}'

# Get GUID from namespaces
oc get namespace -o jsonpath='{.items[*].metadata.labels.tenant-guid}'
```

## Cleanup

### Remove a specific tenant
```bash
# Delete by GUID label
oc delete keycloakuser -n keycloak -l tenant-guid=team-a
oc delete namespace -l tenant-guid=team-a
oc delete rolebinding -A -l tenant-guid=team-a
```

### Remove all tenant resources
```bash
# Delete all tenant resources (BE CAREFUL!)
oc delete keycloakuser -n keycloak -l app.kubernetes.io/component=tenant
oc delete namespace -l app.kubernetes.io/component=tenant
oc delete rolebinding -A -l app.kubernetes.io/component=tenant
```

## Advanced Examples

See `examples/` directory for:
- Multi-environment tenants (dev/stage/prod)
- Department-based tenants
- Workshop/training environments
- Integration with GitOps workflows
