# OCP Cluster Addons

Collection of addons for the OpenShift Container Platform.

These addons are designed to be installed on an existing OpenShift cluster with ArgoCD.

## What is an Addon?

An addon is similar to an OCP4 workload in AgnosticD. Think of it as a library of software that enables developers to enhance their OpenShift cluster with additional features.

## Red Hat Demo Platform

These addons are designed to help developers of the demo platform create their own environments based on OpenShift.

We aim to make it easy for developers to get started with GitOps and ArgoCD for deploying their applications, prioritizing this approach over using Ansible with AgnosticD.

However, this is not the place to find or add your specific demo or lab environment configurations. This is meant for reusable addons that can be utilized by multiple demo environments.

## How to Use

Simply create a new ArgoCD application in your OpenShift cluster and point it to this repository and the desired addon path.

Inside each addon, you’ll find an example ArgoCD application manifest that you can use.

## The charts folder

The `charts` folder is a designated folder containing Helm charts that are published to GitHub’s package registry using GitHub Actions.
