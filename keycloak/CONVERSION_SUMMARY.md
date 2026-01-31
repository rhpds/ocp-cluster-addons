# Ansible to ArgoCD Conversion Summary

This document summarizes the conversion of the `ocp4_workload_authentication_keycloak` Ansible role to ArgoCD applications.

## What Was Converted

### Source: Ansible Role
- **Location**: `roles/ocp4_workload_authentication_keycloak/`
- **Type**: Ansible role with Jinja2 templates
- **Execution**: Imperative (runs once via ansible-playbook)
- **Dependencies**: Ansible, kubernetes.core collection, agnosticd.core collection

### Target: ArgoCD Applications
- **Location**: `roles/ocp4_workload_authentication_keycloak/argocd/`
- **Type**: GitOps with Helm charts
- **Execution**: Declarative (continuously reconciled by ArgoCD)
- **Dependencies**: OpenShift GitOps operator, Git repository

## Architecture Comparison

### Ansible Role Structure
```
roles/ocp4_workload_authentication_keycloak/
├── defaults/main.yml              # Variables
├── tasks/
│   ├── main.yml                   # Entry point
│   ├── workload.yml               # Main provisioning logic
│   └── remove_workload.yml        # Cleanup
└── templates/                     # Jinja2 templates
    ├── postgres_*.yml.j2          # PostgreSQL resources
    ├── keycloak_*.yml.j2          # Keycloak resources
    └── openshift-*.yml.j2         # OAuth resources
```

### ArgoCD Structure
```
argocd/
├── parent-app.yaml                # App of Apps
├── apps/                          # Child app definitions
│   ├── keycloak-operator.yaml
│   ├── keycloak-postgres.yaml
│   ├── keycloak-instance.yaml
│   ├── keycloak-realm.yaml
│   └── keycloak-oauth.yaml
├── charts/                        # Helm charts
│   ├── keycloak-operator/
│   ├── keycloak-postgres/
│   ├── keycloak-instance/
│   ├── keycloak-realm/
│   └── keycloak-oauth/
├── configure.sh                   # Configuration helper
├── README.md                      # Full documentation
├── QUICKSTART.md                  # Quick start guide
└── sync-waves.md                  # Deployment order docs
```

## Component Mapping

| Ansible Component | ArgoCD Component | Notes |
|-------------------|------------------|-------|
| `install_operator` role call | `keycloak-operator` Helm chart | Now uses Subscription/OperatorGroup directly |
| `postgres_database_*.yml.j2` templates | `keycloak-postgres` Helm chart | Deployment, Service, PVC, Secret |
| `keycloak_instance.yml.j2` | `keycloak-instance` Helm chart | Keycloak CR, Service, Route |
| `keycloak_tls_service.yml.j2` | Included in `keycloak-instance` | Service with TLS annotation |
| `keycloak_route.yml.j2` | Included in `keycloak-instance` | OpenShift Route |
| `keycloak_realm_import.yml.j2` | `keycloak-realm` Helm chart | KeycloakRealmImport CR |
| `openshift-oauth.yml.j2` | `keycloak-oauth` Helm chart | OAuth cluster config |
| `openshift-openid-client-secret.yml.j2` | Included in `keycloak-oauth` | OAuth client secret |
| `openshift-admin-crb.yml.j2` | Included in `keycloak-oauth` | ClusterRoleBinding |
| Remove kubeadmin logic | Optional in `keycloak-oauth` | ArgoCD hook job |

## Variable Mapping

| Ansible Variable | Helm Value | Location |
|------------------|------------|----------|
| `ocp4_workload_authentication_keycloak_namespace` | `namespace` | All charts |
| `ocp4_workload_authentication_keycloak_channel` | `operator.channel` | keycloak-operator/values.yaml |
| `ocp4_workload_authentication_keycloak_pgsql_user` | `postgresql.database.user` | keycloak-postgres/values.yaml |
| `ocp4_workload_authentication_keycloak_pgsql_password` | `postgresql.database.password` | keycloak-postgres/values.yaml |
| `openshift_cluster_ingress_domain` | `keycloak.ingressDomain` | keycloak-instance/values.yaml |
| `ocp4_workload_authentication_keycloak_default_realm` | `realm.name` | keycloak-realm/values.yaml |
| `ocp4_workload_authentication_keycloak_num_users` | `realm.users.regular.count` | keycloak-realm/values.yaml |
| `ocp4_workload_authentication_keycloak_user_username_base` | `realm.users.regular.usernameBase` | keycloak-realm/values.yaml |
| `ocp4_workload_authentication_keycloak_admin_username` | `realm.users.admin.username` | keycloak-realm/values.yaml |
| `ocp4_workload_authentication_keycloak_openshift_client_id` | `realm.client.id` | keycloak-realm/values.yaml |
| `ocp4_workload_authentication_keycloak_openshift_client_secret` | `realm.client.secret` | keycloak-realm/values.yaml |

## Features Added in ArgoCD Version

### 1. GitOps Benefits
- **Declarative Configuration**: Desired state stored in Git
- **Automatic Sync**: ArgoCD continuously reconciles state
- **Self-Healing**: Automatically fixes drift from desired state
- **Audit Trail**: Git history provides complete audit trail
- **Rollback**: Easy rollback using Git revert

### 2. App of Apps Pattern
- **Modular Architecture**: Each component is a separate app
- **Independent Lifecycle**: Components can be synced independently
- **Clear Dependencies**: Sync waves ensure proper order
- **Easier Testing**: Test individual components

### 3. Configuration Management
- **Helm Values**: Clean separation of config from templates
- **Multiple Environments**: Easy to create overlays for dev/stage/prod
- **Configuration Helper**: Interactive script to set values
- **Version Control**: All config changes tracked in Git

### 4. Improved Security
- **No Dynamic Passwords**: Passwords set in Git (use SealedSecrets in production)
- **RBAC Integration**: ArgoCD respects OpenShift RBAC
- **Policy Enforcement**: Can use OPA Gatekeeper for validation
- **Secret Management**: Compatible with External Secrets Operator

### 5. Better Observability
- **ArgoCD UI**: Visual representation of app health
- **Sync Status**: See exactly what's in sync or out of sync
- **Resource Topology**: Visual dependency graph
- **Event History**: Track all sync events

## Features Lost (Compared to Ansible)

### 1. Dynamic User Information
The Ansible role used `agnosticd_user_info` to print credentials and save them for users. In ArgoCD:
- **Alternative**: Use `configure.sh` to generate `credentials.txt`
- **Alternative**: Credentials are in Helm values (committed to Git)
- **Production**: Use external secret management (Vault, External Secrets)

### 2. Automatic Password Generation
The Ansible role generated random passwords at runtime. In ArgoCD:
- **Alternative**: Use `configure.sh` to generate passwords
- **Alternative**: Use SealedSecrets or External Secrets Operator
- **Alternative**: Manual password management in values.yaml

### 3. Conditional Logic
The Ansible role had conditional tasks (e.g., only remove kubeadmin if flag set). In ArgoCD:
- **Alternative**: Use Helm conditionals (`{{ if .Values.x }}`)
- **Alternative**: Enable/disable features in values.yaml
- **Alternative**: Use separate apps for optional features

## Migration Path

### For Existing Ansible-Based Deployments

If you have an existing deployment using the Ansible role:

1. **Backup Current State**
   ```bash
   # Export current Keycloak config
   oc get keycloak keycloak -n keycloak -o yaml > backup-keycloak.yaml
   oc get keycloakrealmimport sso -n keycloak -o yaml > backup-realm.yaml
   ```

2. **Extract Current Passwords**
   ```bash
   # Get PostgreSQL password
   oc get secret keycloak-pgsql-user -n keycloak -o jsonpath='{.data.password}' | base64 -d

   # Get OAuth client secret
   oc get secret openid-client-secret-bb6zw -n openshift-config -o jsonpath='{.data.clientSecret}' | base64 -d
   ```

3. **Configure ArgoCD Charts**
   - Use extracted passwords in Helm values
   - Match ingress domain
   - Match realm name and users

4. **Deploy ArgoCD Apps**
   ```bash
   oc apply -f argocd/parent-app.yaml
   ```

5. **Verify**
   - Check all resources are recreated correctly
   - Test login with existing users
   - Verify OAuth still works

### For New Deployments

For new deployments, follow the quickstart guide:

1. Run `./configure.sh` to set up configuration
2. Commit and push to Git
3. Deploy parent app: `oc apply -f parent-app.yaml`
4. Verify deployment

## Deployment Comparison

### Ansible Deployment
```bash
# Clone repository
git clone https://github.com/redhat-cop/agnosticd.git
cd agnosticd/ansible

# Create variable file
cat > myvars.yml <<EOF
ocp4_workload_authentication_keycloak_num_users: 5
ocp4_workload_authentication_keycloak_admin_password: mypassword
EOF

# Run playbook
ansible-playbook -i localhost, -c local \
  workloads/ocp4_workload_authentication_keycloak.yml \
  -e @myvars.yml \
  -e ACTION=provision
```

### ArgoCD Deployment
```bash
# Clone your repository
git clone https://github.com/your-org/your-repo.git
cd your-repo/argocd

# Configure
./configure.sh

# Commit configuration
git add .
git commit -m "Configure Keycloak"
git push

# Deploy
oc apply -f parent-app.yaml

# Watch deployment
oc get applications -n openshift-gitops -w
```

## File Count

### Created Files: 37

#### ArgoCD Applications: 6
- 1 parent app
- 5 child apps

#### Helm Charts: 5
- keycloak-operator (6 files: Chart.yaml, values.yaml, 4 templates)
- keycloak-postgres (6 files: Chart.yaml, values.yaml, 4 templates)
- keycloak-instance (5 files: Chart.yaml, values.yaml, 3 templates)
- keycloak-realm (3 files: Chart.yaml, values.yaml, 1 template)
- keycloak-oauth (6 files: Chart.yaml, values.yaml, 4 templates)

#### Documentation: 5
- README.md (comprehensive guide)
- QUICKSTART.md (quick reference)
- sync-waves.md (deployment order)
- CONVERSION_SUMMARY.md (this file)
- .gitignore

#### Helper Scripts: 1
- configure.sh (interactive configuration)

## Recommendations

### For Development/Testing
- Use the default values with weak passwords
- Use single application deployment for faster iteration
- Keep `removeKubeadmin.enabled: false`

### For Production
- Use `configure.sh` to generate strong passwords
- Integrate with secret management (SealedSecrets, Vault, ESO)
- Use separate Git repositories for different environments
- Implement RBAC policies for ArgoCD
- Enable sync waves for controlled rollout
- Use Git tags for versioning
- Implement backup strategy for Keycloak database

### For Multi-Environment
Create environment-specific values files:
```
argocd/
├── charts/
│   └── keycloak-instance/
│       ├── values.yaml           # Base values
│       ├── values-dev.yaml       # Dev overrides
│       ├── values-stage.yaml     # Stage overrides
│       └── values-prod.yaml      # Prod overrides
```

Reference in Application:
```yaml
helm:
  valueFiles:
    - values.yaml
    - values-prod.yaml  # Environment-specific
```

## Support

For issues or questions:
1. Review README.md for detailed documentation
2. Check sync-waves.md for deployment order issues
3. Review ArgoCD application events
4. Check pod logs in relevant namespaces

## Conclusion

This conversion transforms an imperative Ansible-based deployment into a declarative GitOps workflow. While some dynamic features are lost, the benefits of GitOps (version control, audit trail, automatic reconciliation) outweigh the limitations for most use cases.

The modular architecture with the App of Apps pattern makes it easy to:
- Deploy components independently
- Test changes in isolation
- Maintain configuration in Git
- Roll back changes quickly
- Scale to multiple environments
