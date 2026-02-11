#!/bin/bash

# Keycloak deployment script
#
# Resolves placeholder variables in the ArgoCD Application manifests
# and applies them to the cluster.
#
# Variables can be set via environment or command line:
#
#   # Environment:
#   export INGRESS_DOMAIN=apps.cluster.example.com
#   export PG_PASSWORD=secret
#   ./configure.sh infra
#
#   # Inline:
#   INGRESS_DOMAIN=apps.cluster.example.com PG_PASSWORD=secret ./configure.sh infra
#
# Shared variables:
#   GIT_REPO          Git repository URL         (default: https://github.com/rhpds/ocp-cluster-addons.git)
#   GIT_BRANCH        Git branch or tag          (default: main)
#
# Infra variables:
#   INGRESS_DOMAIN    OpenShift apps domain      (default: auto-detected via oc)
#   PG_PASSWORD       PostgreSQL password         (default: generated)
#   ADMIN_PASSWORD    Keycloak admin password     (default: generated)
#   OAUTH_SECRET      SSO client secret           (default: generated)
#
# Tenant variables:
#   GUID              Tenant identifier           (default: default)
#   USER_COUNT         Number of users to create   (default: 5)
#   USER_PREFIX       Username prefix             (default: user)
#   USER_PASSWORD     Password for all users      (default: generated)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-16
}

usage() {
    echo "Usage: $0 {infra|tenant|both}"
    echo ""
    echo "  infra   Deploy Keycloak infrastructure (operator, instance, PostgreSQL, realm, OAuth)"
    echo "  tenant  Deploy tenant resources (users, namespaces, RBAC)"
    echo "  both    Deploy everything"
    echo ""
    echo "Set variables via environment before running. Unset variables get defaults."
    echo "Run '$0 --help' or see script header for variable reference."
    exit 1
}

if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
fi

MODE="$1"

case "$MODE" in
    infra)  DEPLOY_INFRA=true;  DEPLOY_TENANT=false ;;
    tenant) DEPLOY_INFRA=false; DEPLOY_TENANT=true  ;;
    both)   DEPLOY_INFRA=true;  DEPLOY_TENANT=true  ;;
    *)      usage ;;
esac

# --- Defaults ---

export GIT_REPO="${GIT_REPO:-https://github.com/rhpds/ocp-cluster-addons.git}"
export GIT_BRANCH="${GIT_BRANCH:-main}"

if [ "$DEPLOY_INFRA" = "true" ]; then
    # Auto-detect ingress domain if not provided
    if [ -z "$INGRESS_DOMAIN" ] && command -v oc &> /dev/null; then
        INGRESS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
    fi
    if [ -z "$INGRESS_DOMAIN" ]; then
        echo -e "${RED}ERROR: INGRESS_DOMAIN is required. Set it or log in to the cluster.${NC}" >&2
        exit 1
    fi
    export INGRESS_DOMAIN
    export PG_PASSWORD="${PG_PASSWORD:-$(generate_password)}"
    export ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(generate_password)}"
    export OAUTH_SECRET="${OAUTH_SECRET:-$(generate_password)}"
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    export GUID="${GUID:-default}"
    export USER_COUNT="${USER_COUNT:-5}"
    export USER_PREFIX="${USER_PREFIX:-user}"
    export USER_PASSWORD="${USER_PASSWORD:-$(generate_password)}"
fi

# --- Summary ---

echo -e "${GREEN}=== Keycloak Deployment ===${NC}"
echo ""
echo "Mode:       $MODE"
echo "Git repo:   $GIT_REPO"
echo "Git branch: $GIT_BRANCH"

if [ "$DEPLOY_INFRA" = "true" ]; then
    echo ""
    echo -e "${GREEN}Infrastructure:${NC}"
    echo "  Domain:         $INGRESS_DOMAIN"
    echo "  PG password:    ${PG_PASSWORD:0:4}****"
    echo "  Admin password: ${ADMIN_PASSWORD:0:4}****"
    echo "  OAuth secret:   ${OAUTH_SECRET:0:4}****"
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    echo ""
    echo -e "${GREEN}Tenant:${NC}"
    echo "  GUID:           $GUID"
    echo "  Users:          ${USER_PREFIX}1..${USER_PREFIX}${USER_COUNT}"
    echo "  User password:  ${USER_PASSWORD:0:4}****"
fi

echo ""

# --- Apply ---

ENVSUBST_VARS='${GIT_REPO} ${GIT_BRANCH}'

if [ "$DEPLOY_INFRA" = "true" ]; then
    INFRA_VARS="${ENVSUBST_VARS} "'${INGRESS_DOMAIN} ${PG_PASSWORD} ${ADMIN_PASSWORD} ${OAUTH_SECRET}'
    echo -e "${GREEN}Applying infra/keycloak-infra-app.yaml...${NC}"
    envsubst "$INFRA_VARS" < "${SCRIPT_DIR}/infra/keycloak-infra-app.yaml" | oc apply -f -
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    TENANT_VARS="${ENVSUBST_VARS} "'${GUID} ${USER_COUNT} ${USER_PREFIX} ${USER_PASSWORD}'
    echo -e "${GREEN}Applying tenant/keycloak-tenant-app.yaml...${NC}"
    envsubst "$TENANT_VARS" < "${SCRIPT_DIR}/tenant/keycloak-tenant-app.yaml" | oc apply -f -
fi

echo ""
echo -e "${GREEN}Done.${NC}"

# --- Save credentials ---

CREDS_FILE="${SCRIPT_DIR}/credentials.txt"
cat > "$CREDS_FILE" <<EOF
Keycloak Deployment Credentials
================================
Generated: $(date)
Mode: $MODE

EOF

if [ "$DEPLOY_INFRA" = "true" ]; then
    cat >> "$CREDS_FILE" <<EOF
Domain: $INGRESS_DOMAIN
Keycloak URL: https://sso.$INGRESS_DOMAIN

PostgreSQL password: $PG_PASSWORD
OAuth client secret: $OAUTH_SECRET
Admin password:      $ADMIN_PASSWORD

EOF
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    cat >> "$CREDS_FILE" <<EOF
GUID: $GUID
Users: ${USER_PREFIX}1 .. ${USER_PREFIX}${USER_COUNT}
User password: $USER_PASSWORD

EOF
fi

echo -e "Credentials saved to: ${YELLOW}$CREDS_FILE${NC}"
echo -e "${RED}Do not commit credentials.txt to git.${NC}"
