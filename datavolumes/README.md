# datavolumes - create datavolumes for RHDP virt environments

This repository contains a Helm chart

## Overview

To speed up the creation of mulitple virtual machines, this Helm chart can be used to create DataVolumes and populate them with a qcow2 image.

All datavolumes are created in the namespace `default`.
RBAC is included.

Default, known-good, values for the DataVolumes can be found in the `values.yaml` file.

This Helm chart defaults to using IBM's Cloud Object Storage (COS) as the storage backend for the qcow2 images.
Paths to the AWS S3 buckets is also provided in the `values.yaml` file, commented out.

When used with an ArgoCD Application, this Helm chart provides the following functionalities:

1. **Creates DataVolumes and Populates them with a qcow2 image**

## Usage

The namespace to contain your VMs will need this RoleBinding.
The ClusterRole `datavolume-cloner` is provided by this Helm chart.

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: datavolume-allow-clone-sa-{{ $.Values.namespace }}
  namespace: default
subjects:
- kind: ServiceAccount
  name: default
  namespace: {{ $.Values.namespace }}
roleRef:
  kind: ClusterRole
  name: datavolume-cloner
  apiGroup: rbac.authorization.k8s.io
```

## Prerequisites

- **ArgoCD**: Make sure you have ArgoCD installed and configured in your OpenShift cluster.
