# Keycloak/RHSSO Helm Chart for ArgoCD

This repository contains a Helm chart designed for deploying Keycloak/RHSSO with ArgoCD.

## Overview

When used with an ArgoCD Application, this Helm chart provides the following functionalities:

1. **Installs the RHSSO Operator**: Deploys the Red Hat Single Sign-On (RHSSO) Operator to your OpenShift cluster.
2. **Creates the Keycloak Instance**: Instantiates a Keycloak server based on the RHSSO Operator.
3. **Creates an `openshift` Keycloak Client**: Configures a client in Keycloak specifically for OpenShift integration.
4. **Creates an Admin User**: Sets up an admin user to login to OpenShift.
5. **Configures OpenShift OAuth**: Integrates Keycloak with OpenShift OAuth, allowing users to log in to OpenShift using RHSSO.

## Usage

To use this Helm chart with ArgoCD, you can refer to the [application-rhsso.yaml](/bootstrap/templates/application-rhsso.yaml) file provided in this repository.

## Prerequisites

- **ArgoCD**: Make sure you have ArgoCD installed and configured in your OpenShift cluster.
