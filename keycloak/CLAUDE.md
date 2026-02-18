# Migrating from Ansible to GitOps

These instructions define the Demo Platform's GitOps model for deploying to an OpenShift cluster.

Secondarily, they support the migration of Ansible Workloads into the Demo Platform's GitOps model.

## Definitions

### Ansible Workload

An Ansible workload in the Demo Platform system is a set of Ansible tasks and templates.

These workloads often implement the installation and configuration of software on a target system.

These workloads often also configure users on the target system, relying on a prior ansible collection 'ocp4_workload_authentication' to create the users.

This is no longer the accepable pattern.  Users will now be created as Keycloak users.  The presence of the Keycloak operator is now required.

### GitOps addon (aka workload)

This GitOps pattern defines three main components:

* Platform
* Infra
* Tenant

These components may be all in the same git repo, or may be spread across multiple repos.

Example 1 - Single Repo:
`ocp-cluster-addons` repo

* Platform is in the `/keycloak/platform` path.
* Infra is in the `/keycloak/info` path.
* Tenant is in the `/keycloak/tenant` path.

Example 2 - Multiple Repos, Platform separate:

Platform repo: `ocp-cluster-platform`
* Platform is in the `ocp-cluster-platform/keycloak/platform` path.

Infra/Tenant repo: `ocp-cluster-addons`

* Infra is in the `/keycloak/info` path.
* Tenant is in the `/keycloak/tenant` path.

### Platform

Is the under the sole ownership of the Demo Platform Team.

It tunes, scales, and configures the cluster for the particular needs of the Lab being deployed.

It is meant to set up the cluster with Operators, RBAC, Storage, Networking, etc.

It sets up Nodes, nodepools, etc.

It sets up Keycloak Operator, database, etc.  But not specific keycloak users.  That's handled by the Tenant.

### Infra

Is the under the ownership of the Lab Authors and the Demo Platofrm Content Team.

It does futher cluster-scoped configuration as it applies to the needs of Tenants.

It updates operators, creates CRs for those products.

It sets up RBAC for the expected user groups, projectrequesttemplates, etc.

### Tenant

The Tenant is under the ownership of the Lab Authors and the Demo Platofrm Content Team.

A tenant is identified by a GUID sent from the bootstrapper.

A tenant defines a set of OpenShift users and their namespaces and RBAC, as well as product or demo specific configurations, like deploying sample apps, vms, load generators, etc.

#### Tenant Users

Tenant users should be created as a Keycloak user.

The tenant is expected to create namespaces and RBAC for its users.

Tenant gitops may create resources scoped to user own namespaces, which gitops will create for them.

Tenant user names may be a list of explicity user names, with a GUID suffix.  Or they may be generated from a prefix and a start number, with the GUID suffix.

Tenant namespaces may be generated from a prefix and a start number, with a GUID suffix, or an explicity list of namespaces + GUID.

Tenant RBAC may be generated from a prefix and a start number, with a GUID suffix, or an explicity list of users + GUID.

# Migration: Ansible workload -> GitOps addon migration

Parse the ansible workload and separate what belongs to each of platform, infra, and tenant.

Try to be brief.  Do not create additional charts where not necessary.  The goals is to install the one product or "addon."

Ideally, each of platform, infra, and tenant should be single charts, but complex scenarios and the goal of easy re-use should be considered.

# Required GitOps addon structure

An example addon is "keycloak".

These gitops "addons" aka workloads do not implement the bootstrap charts.  They are addressed by the bootstrap charts via applications in the bootstrap charts.

Create a new addon in the directory `ocp-cluster-addons/<PRODUCT>`, which includes helm charts: on called "infra" and one called "tenant".

The Infra chart should install or configure the operator and any depenedncies that are general to all tenants.

### Passing values and argo parameters

Create a sample application to show users how to call each of the platform, infra, and tenant helm charts.
Put them in the directory `ocp-cluster-addons/<PRODUCT>/<CHART>`.

Expect all parameters to be passed via application values in .spec.helm.values as in the example that follows:
```

In the sample application, make sure that the three default helm values set by the bootstrapper are passed to the charts.

Example:

deployer:
  domain: <ingress domain>
  apiUrl: <api url>
  guid: <guid>
````

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: this
    targetRevision: main
    path: 3scale
    helm:
      values: |
        namespace: 3scale
        operator:
          channel: threescale-2.14
          startingCSV: 3scale-operator.x.y.z
          installPlanApproval: Manual
        apimanager:
          wildcardDomain: apps.cluster.opentlc.com
          tenantName: demo
          llmMetrics:
            name: llm-metrics
            version: 0.1
        helper-status-checker:
          approver: true
          checks:
            - operatorName: rhbk-operator
              namespace:
                name: 3scale
              syncwave: '1'
              serviceAccount:
                name: "3scale-status-checker"
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak

Make sure any use of a CRD has SkipDryRunOnMissingResource: true and sufficient retries to allow the operator to install the CRD properly.


# GitOps creation process

If this is a migration from Ansible to GitOPs:
Examine the ansible workload and determine which features are part of the infrastructure and which are the resources a tenant will need.

If this is a new addon:
Query the user for details necessary to create the addon.

## The bootstrap app and chart, as found in core_workloads repo

The deployer creates new applications and charts called 'boostrap' on the argo server.

There are four possible bootstrapper apps, with their attendant charts:

* /bootstrap/template <- when present will run all present platform, infra, and tenant charts
* /platform/bootstrap/template
* /infra/bootstrap/template
* /tenant/bootstrap/template

In the template directory the author places the argo apps that call helm other argo apps or helm charts.

It holds the helm values and argo parameters for the infra or the tenant.

## Operator CatalogSources

Sometimes upstream catalogsources become corrupt, and we must revert to older catalog sources.

When creating the option to use a catalogsource that is not the default, there
is no need to mention disconnected environments. We do not run these in a
disconencted environment.  The catalogsource we use at quay.io is to pin
catalogsources at particular versions, which often become inaccessible to online openshift
installs.  

