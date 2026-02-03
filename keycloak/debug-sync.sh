#!/bin/bash
# Quick debug script to see what's causing sync timeouts

echo "=== ArgoCD Application Status ==="
oc get applications -n openshift-gitops | grep keycloak

echo ""
echo "=== Checking which app is stuck ==="
for app in $(oc get applications -n openshift-gitops -o name | grep keycloak); do
    echo ""
    echo "App: $app"
    oc get $app -n openshift-gitops -o jsonpath='{.metadata.name}: {.status.sync.status} - {.status.health.status}{"\n"}'
done

echo ""
echo "=== Resources in keycloak namespace ==="
oc get all -n keycloak

echo ""
echo "=== Operator Status ==="
oc get subscription,csv,installplan -n keycloak

echo ""
echo "=== Keycloak CRs ==="
oc get keycloak,keycloakrealmimport -n keycloak 2>/dev/null || echo "No Keycloak CRs yet"

echo ""
echo "=== Pods Status ==="
oc get pods -n keycloak

echo ""
echo "=== Recent Events ==="
oc get events -n keycloak --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=== Checking for common issues ==="

# Check if operator CSV is ready
CSV_READY=$(oc get csv -n keycloak -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$CSV_READY" = "Succeeded" ]; then
    echo "✓ Operator CSV is ready"
else
    echo "✗ Operator CSV status: $CSV_READY"
    echo "  This is likely causing the timeout"
fi

# Check if PostgreSQL is ready
PG_READY=$(oc get statefulset keycloak-postgresql -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$PG_READY" = "1" ]; then
    echo "✓ PostgreSQL is ready"
else
    echo "✗ PostgreSQL ready replicas: ${PG_READY:-0}/1"
    echo "  This may be causing the timeout"
fi

# Check if Keycloak instance is ready
KC_READY=$(oc get keycloak keycloak -n keycloak -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$KC_READY" = "True" ]; then
    echo "✓ Keycloak instance is ready"
else
    echo "✗ Keycloak instance ready: ${KC_READY:-Unknown}"
    echo "  This may be causing the timeout"
fi
