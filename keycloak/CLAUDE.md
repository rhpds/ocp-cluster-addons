
Create a new addon in the directory `ocp-cluster-addons/<PRODUCT>`, which includes two helm charts: on called "infra" and one called "tenant".

The Infra chart should install the operator and any depenedncies that are general to all tenants.

Examine the ansible role and determine which features are part of the infrastructure and which are the resources a tenant will need.

Expect all parameters to be passed via application values in .spec.helm.values as in the example that follows:
```

Make sure that the three default helm values set by the bootstrapper (not defined here) are passed to the charts.
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
