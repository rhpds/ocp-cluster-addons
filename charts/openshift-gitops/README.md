# Red Hat OpenShift GitOps

This repository contains a Helm chart designed for installing OpenShift GitOps.

## Overview

This chart installs the OpenShift GitOps operator and configures the ArgoCD instance.

You should not attempt to do both at the same time. The operator must be installed before the ArgoCD instance can be configured.

For this reason, the chart has two separate values that can be set to `true` to install the operator or configure the ArgoCD instance.

## Usage

To install the OpenShift GitOps operator, run the following command:

```shell
helm template https://github.com/rhpds/ocp-cluster-addons/releases/download/openshift-gitops-1.0.0/openshift-gitops-1.0.0.tgz --set operator.install=true | oc apply -f -
```

To configure the ArgoCD instance, run the following command:

```shell
helm template https://github.com/rhpds/ocp-cluster-addons/releases/download/openshift-gitops-1.0.0/openshift-gitops-1.0.0.tgz --set argocd.install=true | oc apply -f -
```

## OpenShift Console Plugin

To enable the OpenShift GitOps plugin in the OpenShift console, run the following command:

```shell
oc patch console.operator cluster --type json -p '[{"op": "add", "path": "/spec/plugins/-", "value": "gitops-plugin"}]'
```
