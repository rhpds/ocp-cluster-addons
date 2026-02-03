# Keycloak Operator Chart

This Helm chart installs the Red Hat Build of Keycloak (RHBK) operator using the Operator Lifecycle Manager (OLM).

## Features

- Automated operator installation via OLM Subscription
- Support for custom catalog sources (useful for disconnected/air-gapped environments)
- CSV version pinning for controlled upgrades
- Automated InstallPlan approval for GitOps workflows

## Configuration

### Basic Installation

The default configuration installs the operator with automatic approval:

```yaml
namespace: keycloak

operator:
  name: rhbk-operator
  channel: stable-v26.2
  installPlanApproval: Automatic
```

### Pinning to a Specific CSV Version

To pin the operator to a specific version and control upgrades:

```yaml
operator:
  name: rhbk-operator
  channel: stable-v26.2
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"

  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
```

**How it works:**
1. The subscription is created with `installPlanApproval: Manual`
2. The `startingCSV` specifies the exact version to install
3. A Job automatically approves the InstallPlan after verifying the CSV matches
4. Operator upgrades require manual intervention or values file updates

### Using Custom Catalog Source

For disconnected environments or to use a specific catalog snapshot:

```yaml
operator:
  catalogSource:
    enabled: true
    name: custom-redhat-catalog
    image: quay.io/gpte-devops-automation/olm_snapshot_redhat_catalog
    tag: v4.20_2025_10_23
```

## InstallPlan Approver

The InstallPlan approver is a Kubernetes Job that automatically approves InstallPlans when using `installPlanApproval: Manual`. This is useful for GitOps workflows where you want to control operator versions through Git.

### Configuration Options

```yaml
operator:
  installPlanApprover:
    enabled: false                # Enable the approver job
    enforceCSVMatch: true         # Only approve if CSV matches startingCSV
    timeout: 600                  # Job timeout in seconds
    backoffLimit: 3               # Number of retries
    image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
```

### Behavior

**When `enforceCSVMatch: true` (recommended):**
- Only approves if the InstallPlan CSV matches the specified `startingCSV`
- Fails if there's a mismatch (prevents unwanted upgrades)
- Requires `startingCSV` to be set

**When `enforceCSVMatch: false`:**
- Approves any InstallPlan for the subscription
- Useful when you want manual approval workflow but don't care about exact version

### ArgoCD Sync Waves

The approver job uses ArgoCD annotations to ensure proper ordering:

- **Sync Wave 0**: Namespace, OperatorGroup, CatalogSource (if enabled)
- **Sync Wave 1**: Subscription, RBAC for approver
- **Sync Wave 2**: InstallPlan approver job

This ensures the job runs after the subscription is created and can find the InstallPlan.

## Examples

### Example 1: Production with Version Control

Pin to specific version with automated approval:

```yaml
operator:
  name: rhbk-operator
  channel: stable-v26.2
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"

  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
    timeout: 600
```

### Example 2: Development with Latest Version

Always use latest version in channel:

```yaml
operator:
  name: rhbk-operator
  channel: stable-v26.2
  installPlanApproval: Automatic
  startingCSV: ""

  installPlanApprover:
    enabled: false
```

### Example 3: Disconnected Environment with Pinned Version

Use custom catalog with version pinning:

```yaml
operator:
  name: rhbk-operator
  channel: stable-v26.2
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"

  catalogSource:
    enabled: true
    name: custom-redhat-catalog
    image: quay.io/gpte-devops-automation/olm_snapshot_redhat_catalog
    tag: v4.20_2025_10_23

  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
```

## Upgrading the Operator

### With Version Pinning (Recommended)

1. Update the `startingCSV` in your values file:
   ```yaml
   operator:
     startingCSV: "rhbk-operator.v26.3.0"  # Changed from v26.2.0
   ```

2. Commit and push the change

3. ArgoCD will sync and the approver job will:
   - Wait for the new InstallPlan
   - Verify it matches the new CSV
   - Approve it automatically

### Without Version Pinning

With `installPlanApproval: Automatic`, operator upgrades happen automatically when:
- A new version is published to the catalog
- The catalog is refreshed (every 30m by default)

## Troubleshooting

### Check InstallPlan Status

```bash
oc get installplan -n keycloak
oc describe installplan <installplan-name> -n keycloak
```

### Check Subscription Status

```bash
oc get subscription rhbk-operator -n keycloak -o yaml
```

### View Approver Job Logs

```bash
oc logs -n keycloak job/rhbk-operator-installplan-approver
```

### Common Issues

**InstallPlan not approved:**
- Check if approver job is enabled
- Verify RBAC permissions
- Check job logs for errors

**CSV mismatch error:**
- Verify the `startingCSV` exists in the channel
- Check catalog source health
- List available CSVs: `oc get packagemanifest rhbk-operator -o yaml`

**Job timeout:**
- Increase `installPlanApprover.timeout`
- Check if subscription is healthy
- Verify catalog source is accessible

## Resources Created

This chart creates the following resources:

1. **Namespace** - Where the operator runs
2. **OperatorGroup** - Configures operator target namespaces
3. **CatalogSource** (optional) - Custom operator catalog
4. **Subscription** - OLM subscription for the operator
5. **ServiceAccount** (if approver enabled) - For approver job
6. **Role** (if approver enabled) - Permissions to manage InstallPlans
7. **RoleBinding** (if approver enabled) - Binds role to service account
8. **Job** (if approver enabled) - Approves InstallPlans

## See Also

- [Keycloak Operator Documentation](https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak)
- [OLM Documentation](https://olm.operatorframework.io/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
