# CSV Pinning and InstallPlan Approver Feature

This document describes the new CSV pinning and automated InstallPlan approval features added to the Keycloak operator chart.

## Overview

Two major features have been added:

1. **CSV Pinning** - Pin the operator to a specific ClusterServiceVersion (CSV) for controlled upgrades
2. **InstallPlan Approver Job** - Automated approval of InstallPlans for GitOps workflows

## Changes Made

### 1. Operator Chart Enhancements

#### Files Modified:
- `infra/charts/keycloak-operator/values.yaml` - Added configuration options
- `infra/charts/keycloak-operator/templates/subscription.yaml` - Added sync wave annotation
- `infra/charts/keycloak-operator/templates/namespace.yaml` - Added sync wave annotation
- `infra/charts/keycloak-operator/templates/operatorgroup.yaml` - Added sync wave annotation
- `infra/charts/keycloak-operator/templates/catalogsource.yaml` - Added sync wave annotation

#### Files Created:
- `infra/charts/keycloak-operator/README.md` - Comprehensive documentation
- `infra/charts/keycloak-operator/templates/installplan-approver-sa.yaml` - ServiceAccount for job
- `infra/charts/keycloak-operator/templates/installplan-approver-role.yaml` - RBAC permissions
- `infra/charts/keycloak-operator/templates/installplan-approver-rolebinding.yaml` - Role binding
- `infra/charts/keycloak-operator/templates/installplan-approver-job.yaml` - Main approver job

### 2. Example Configurations

#### Files Created:
- `infra/examples/pinned-operator-version.yaml` - Example with CSV pinning
- `infra/examples/disconnected-operator.yaml` - Example for air-gapped environments

## New Configuration Options

### values.yaml Structure

```yaml
operator:
  # Existing options
  name: rhbk-operator
  channel: stable-v26.2

  # NEW: Control approval mode
  installPlanApproval: Manual  # or Automatic

  # NEW: Pin to specific CSV
  startingCSV: "rhbk-operator.v26.2.0"

  # NEW: InstallPlan Approver configuration
  installPlanApprover:
    enabled: false              # Enable the approver job
    enforceCSVMatch: true       # Only approve matching CSV
    timeout: 600                # Job timeout (seconds)
    backoffLimit: 3             # Retry attempts
    image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
```

## How It Works

### Without InstallPlan Approver (Default)

```yaml
operator:
  installPlanApproval: Automatic
  installPlanApprover:
    enabled: false
```

- Operator upgrades happen automatically when new versions are available
- No manual intervention required
- Latest version in channel is always installed

### With CSV Pinning and Approver

```yaml
operator:
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"
  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
```

**Workflow:**

1. **Subscription Created** (Wave 0-1)
   - OLM creates an InstallPlan for the specified CSV
   - InstallPlan remains in pending state (requires approval)

2. **Approver Job Runs** (Wave 2)
   - Waits for InstallPlan to be created
   - Retrieves InstallPlan details
   - Verifies CSV matches `startingCSV` (if `enforceCSVMatch: true`)
   - Approves the InstallPlan
   - Operator installation proceeds

3. **Upgrade Process**
   - Update `startingCSV` in values file
   - Commit and push to Git
   - ArgoCD syncs the change
   - New approver job runs and approves new version

## Sync Wave Ordering

Resources are deployed in this order:

- **Wave 0**: Namespace, OperatorGroup, CatalogSource
- **Wave 1**: Subscription, RBAC (SA, Role, RoleBinding)
- **Wave 2**: InstallPlan Approver Job

This ensures the job runs after the subscription creates an InstallPlan.

## Use Cases

### Use Case 1: Production Environment - Controlled Upgrades

Pin operator to known-good version, upgrade only when validated:

```yaml
operator:
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"
  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
```

**Benefits:**
- Prevents automatic upgrades
- Control upgrade timing through Git commits
- Validate in dev/test before updating production
- Full audit trail of operator versions

### Use Case 2: Development Environment - Latest Version

Always use the latest available version:

```yaml
operator:
  installPlanApproval: Automatic
  startingCSV: ""
  installPlanApprover:
    enabled: false
```

**Benefits:**
- Automatic updates
- Always testing latest features
- Minimal configuration

### Use Case 3: Disconnected/Air-Gapped Environment

Use custom catalog with pinned version:

```yaml
operator:
  installPlanApproval: Manual
  startingCSV: "rhbk-operator.v26.2.0"

  catalogSource:
    enabled: true
    name: custom-redhat-catalog
    image: your-registry.example.com/catalog
    tag: v4.20_snapshot

  installPlanApprover:
    enabled: true
    enforceCSVMatch: true
```

**Benefits:**
- Works in disconnected environments
- Use mirrored operator catalogs
- Control which versions are available

## Troubleshooting

### Check InstallPlan Status

```bash
# List all InstallPlans
oc get installplan -n keycloak

# Describe specific InstallPlan
oc describe installplan <name> -n keycloak

# View InstallPlan YAML
oc get installplan <name> -n keycloak -o yaml
```

### Check Approver Job Logs

```bash
# Follow job logs
oc logs -n keycloak job/rhbk-operator-installplan-approver -f

# View completed job logs
oc logs -n keycloak job/rhbk-operator-installplan-approver
```

### Check Subscription Status

```bash
# View subscription
oc get subscription rhbk-operator -n keycloak -o yaml

# Check current CSV
oc get subscription rhbk-operator -n keycloak \
  -o jsonpath='{.status.currentCSV}'

# Check installed CSV
oc get subscription rhbk-operator -n keycloak \
  -o jsonpath='{.status.installedCSV}'
```

### Common Issues

#### Issue: CSV Mismatch Error

**Symptom:** Approver job fails with CSV mismatch error

**Cause:** The InstallPlan CSV doesn't match the specified `startingCSV`

**Solutions:**
1. Verify the CSV exists in the channel:
   ```bash
   oc get packagemanifest rhbk-operator -o yaml
   ```
2. Check if you're using the correct channel
3. Verify custom catalog source has the CSV
4. Set `enforceCSVMatch: false` to approve anyway

#### Issue: Job Timeout

**Symptom:** Approver job times out waiting for InstallPlan

**Cause:** InstallPlan not created, or subscription has issues

**Solutions:**
1. Check subscription status
2. Verify catalog source is healthy
3. Increase `timeout` value
4. Check operator namespace events

#### Issue: Permission Denied

**Symptom:** Job fails with RBAC errors

**Cause:** ServiceAccount missing permissions

**Solutions:**
1. Verify Role and RoleBinding are created
2. Check ServiceAccount exists
3. Review job logs for specific permission error

## Migration Guide

### From Automatic to Pinned Version

**Current configuration:**
```yaml
operator:
  installPlanApproval: Automatic
```

**Migrating to pinned version:**

1. Determine current installed CSV:
   ```bash
   oc get csv -n keycloak | grep rhbk-operator
   ```

2. Update values.yaml:
   ```yaml
   operator:
     installPlanApproval: Manual
     startingCSV: "rhbk-operator.v26.2.0"  # Use current version
     installPlanApprover:
       enabled: true
       enforceCSVMatch: true
   ```

3. Commit and deploy:
   ```bash
   git add infra/charts/keycloak-operator/values.yaml
   git commit -m "Enable CSV pinning for keycloak operator"
   git push
   ```

4. Verify:
   ```bash
   oc get installplan -n keycloak
   oc logs -n keycloak job/rhbk-operator-installplan-approver
   ```

## Testing

### Validate Template Rendering

```bash
# Test with approver enabled
helm template test infra/charts/keycloak-operator \
  --set operator.installPlanApprover.enabled=true \
  --set operator.startingCSV="rhbk-operator.v26.2.0" \
  --set operator.installPlanApproval=Manual

# Test with approver disabled
helm template test infra/charts/keycloak-operator \
  --set operator.installPlanApprover.enabled=false
```

### Deploy to Test Environment

```bash
# Deploy with pinned version
helm upgrade --install keycloak-operator \
  infra/charts/keycloak-operator \
  -f infra/examples/pinned-operator-version.yaml

# Watch the approver job
oc get jobs -n keycloak -w

# Follow logs
oc logs -n keycloak job/rhbk-operator-installplan-approver -f
```

## Benefits

1. **GitOps-Friendly**: Operator versions controlled through Git
2. **Audit Trail**: All version changes tracked in Git commits
3. **Controlled Upgrades**: Prevent unexpected operator upgrades
4. **Environment Parity**: Use same version across dev/test/prod
5. **Rollback Support**: Git revert to roll back to previous version
6. **Compliance**: Meet requirements for change management processes

## See Also

- [Operator Chart README](infra/charts/keycloak-operator/README.md)
- [Example: Pinned Version](infra/examples/pinned-operator-version.yaml)
- [Example: Disconnected Environment](infra/examples/disconnected-operator.yaml)
- [OLM Documentation](https://olm.operatorframework.io/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
