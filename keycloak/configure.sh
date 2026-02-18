#!/bin/bash

# Keycloak deployment script
#
# Resolves placeholder variables in the ArgoCD Application manifests
# and applies them to the cluster.
#
#   ./configure.sh infra
#   ./configure.sh tenant <GUID>
#   ./configure.sh both <GUID>
#   ./configure.sh delete <GUID>
#   ./configure.sh tenant <GUID> --cleanup    # enable PreDelete realm cleanup Job
#
#   # Override variables via environment:
#   INGRESS_DOMAIN=apps.cluster.example.com PG_PASSWORD=secret ./configure.sh both xyzzy
#
#   # Explicit user list (comma-separated):
#   USERS=alice,bob,charlie ./configure.sh tenant xyzzy
#
# Shared variables:
#   GIT_REPO          Git repository URL         (default: https://github.com/rhpds/ocp-cluster-addons.git)
#   GIT_BRANCH        Git branch or tag          (default: keycloak-wip)
#
# Infra variables:
#   INGRESS_DOMAIN    OpenShift apps domain      (default: auto-detected via oc)
#   PG_PASSWORD       PostgreSQL password         (default: generated)
#   ADMIN_PASSWORD    Keycloak admin password     (default: generated)
#   OAUTH_SECRET      SSO client secret           (default: generated)
#
# Tenant variables (GUID is passed as a positional argument):
#   GUID              Tenant identifier           (required for tenant/both/delete)
#   USER_PASSWORD     Password for all users      (default: generated)
#
#   Generate mode (default when USERS is not set):
#     USER_COUNT      Number of users to create   (default: 5)
#     USER_PREFIX     Username prefix             (default: user)
#
#   Explicit mode (when USERS is set):
#     USERS           Comma-separated usernames   (e.g. alice,bob,charlie)

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
    echo "Usage: $0 infra"
    echo "       $0 tenant <GUID>"
    echo "       $0 both <GUID>"
    echo "       $0 delete <GUID>"
    echo ""
    echo "  infra          Deploy Keycloak infrastructure (operator, instance, PostgreSQL, realm, OAuth)"
    echo "  tenant <GUID>  Deploy tenant resources (users, namespaces, RBAC) for the given GUID"
    echo "  both <GUID>    Deploy everything"
    echo "  delete <GUID>  Delete Keycloak users from realm, then remove the tenant ArgoCD Application"
    echo ""
    echo "Options:"
    echo "  --cleanup      Enable PreDelete hook Job that deletes the tenant realm"
    echo "                 from Keycloak when the ArgoCD Application is deleted."
    echo "                 Requires ArgoCD v2.10+."
    echo ""
    echo "  Set USERS=alice,bob,charlie to specify explicit usernames."
    echo "  Otherwise users are generated as user1, user2, ... userN."
    echo ""
    echo "Set variables via environment before running. Unset variables get defaults."
    echo "Run '$0 --help' or see script header for variable reference."
    exit 1
}

if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
fi

MODE="$1"
shift

# Parse optional flags and positional GUID from remaining args
CLEANUP_ENABLED=false
GUID_ARG=""
for arg in "$@"; do
    case "$arg" in
        --cleanup) CLEANUP_ENABLED=true ;;
        -*)        echo -e "${RED}ERROR: Unknown option: ${arg}${NC}" >&2; usage ;;
        *)         GUID_ARG="$arg" ;;
    esac
done

# --- Delete mode ---
# KeycloakRealmImport is a one-shot import — deleting the CR does NOT delete
# the realm.  We must delete the realm via the Keycloak Admin REST API first,
# then remove the ArgoCD Application.
if [ "$MODE" = "delete" ]; then
    GUID="${GUID_ARG:-${GUID:-}}"
    if [ -z "$GUID" ]; then
        echo -e "${RED}ERROR: GUID is required. Usage: $0 delete <GUID>${NC}" >&2
        exit 1
    fi

    KC_NAMESPACE="${KC_NAMESPACE:-keycloak}"
    APP_NAME="tenant-${GUID}-keycloak"
    REALM_NAME="tenant-${GUID}"

    echo -e "${GREEN}=== Delete tenant: ${GUID} ===${NC}"

    # Discover the Keycloak URL from the route
    KC_URL=$(oc get route keycloak -n "${KC_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [ -z "$KC_URL" ]; then
        echo -e "${YELLOW}WARNING: Could not find Keycloak route in ${KC_NAMESPACE}. Skipping realm deletion.${NC}"
    else
        KC_URL="https://${KC_URL}"

        # Read admin credentials from the secret
        KC_ADMIN_USER=$(oc get secret keycloak-initial-admin -n "${KC_NAMESPACE}" -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
        KC_ADMIN_PASS=$(oc get secret keycloak-initial-admin -n "${KC_NAMESPACE}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

        if [ -z "$KC_ADMIN_USER" ] || [ -z "$KC_ADMIN_PASS" ]; then
            echo -e "${YELLOW}WARNING: Could not read admin credentials from keycloak-initial-admin secret. Skipping realm deletion.${NC}"
        else
            echo "Obtaining admin token from ${KC_URL}..."
            TOKEN=$(curl -sk -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
                -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASS}" \
                | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)

            if [ -z "$TOKEN" ]; then
                echo -e "${YELLOW}WARNING: Failed to obtain admin token. Skipping realm deletion.${NC}"
            else
                echo "Deleting realm ${REALM_NAME}..."
                HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' -X DELETE \
                    "${KC_URL}/admin/realms/${REALM_NAME}" \
                    -H "Authorization: Bearer ${TOKEN}")

                case "$HTTP_CODE" in
                    204) echo -e "${GREEN}Realm ${REALM_NAME} deleted.${NC}" ;;
                    404) echo -e "${YELLOW}Realm ${REALM_NAME} not found (already deleted).${NC}" ;;
                    *)   echo -e "${RED}Unexpected response deleting realm: HTTP ${HTTP_CODE}${NC}" ;;
                esac
            fi
        fi
    fi

    # Delete the ArgoCD Application (prunes remaining K8s resources)
    echo ""
    echo "Deleting ArgoCD Application ${APP_NAME}..."
    oc delete application "${APP_NAME}" -n openshift-gitops --ignore-not-found

    echo -e "${GREEN}Tenant ${GUID} deleted.${NC}"
    exit 0
fi

# --- Deploy modes ---
case "$MODE" in
    infra)  DEPLOY_INFRA=true;  DEPLOY_TENANT=false ;;
    tenant) DEPLOY_INFRA=false; DEPLOY_TENANT=true  ;;
    both)   DEPLOY_INFRA=true;  DEPLOY_TENANT=true  ;;
    *)      usage ;;
esac

# GUID is required for tenant and both modes
if [ "$DEPLOY_TENANT" = "true" ]; then
    export GUID="${GUID_ARG:-${GUID:-}}"
    if [ -z "$GUID" ]; then
        echo -e "${RED}ERROR: GUID is required. Usage: $0 $MODE <GUID>${NC}" >&2
        exit 1
    fi
fi

# --- Defaults ---

export GIT_REPO="${GIT_REPO:-https://github.com/rhpds/ocp-cluster-addons.git}"
export GIT_BRANCH="${GIT_BRANCH:-keycloak-wip}"

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
    export USER_PASSWORD="${USER_PASSWORD:-$(generate_password)}"

    if [ "$CLEANUP_ENABLED" = "true" ]; then
        export CLEANUP_BLOCK="        cleanup:
          realmDeletion:
            enabled: true"
    else
        export CLEANUP_BLOCK=""
    fi

    if [ -n "$USERS" ]; then
        # --- Explicit mode ---
        USER_MODE="explicit"
        IFS=',' read -ra USER_ARRAY <<< "$USERS"

        USERNAMES_YAML=""
        NAMESPACES_YAML=""
        USER_DISPLAY=""
        for u in "${USER_ARRAY[@]}"; do
            u=$(echo "$u" | xargs)  # trim whitespace
            USERNAMES_YAML="${USERNAMES_YAML}
              - ${u}"
            NAMESPACES_YAML="${NAMESPACES_YAML}
              - ${u}-project"
            USER_DISPLAY="${USER_DISPLAY:+${USER_DISPLAY}, }${u}"
        done

        export USERS_BLOCK="        users:
          mode: explicit
          explicit:
            usernames:${USERNAMES_YAML}
            appendGuid: true
          password: ${USER_PASSWORD}"

        export NAMESPACES_BLOCK="        namespaces:
          mode: explicit
          explicit:
            names:${NAMESPACES_YAML}"
    else
        # --- Generate mode ---
        USER_MODE="generate"
        export USER_COUNT="${USER_COUNT:-5}"
        export USER_PREFIX="${USER_PREFIX:-user}"
        USER_DISPLAY="${USER_PREFIX}1..${USER_PREFIX}${USER_COUNT}"

        export USERS_BLOCK="        users:
          mode: generate
          generate:
            count: ${USER_COUNT}
            prefix: ${USER_PREFIX}
            startNumber: 1
          password: ${USER_PASSWORD}"

        export NAMESPACES_BLOCK="        namespaces:
          mode: generate
          generate:
            count: ${USER_COUNT}
            prefix: ${USER_PREFIX}
            suffix: -project
            startNumber: 1"
    fi
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
    echo "  User mode:      $USER_MODE"
    echo "  Users:          $USER_DISPLAY"
    echo "  User password:  ${USER_PASSWORD:0:4}****"
    echo "  Realm cleanup:  $CLEANUP_ENABLED"
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
    TENANT_VARS="${ENVSUBST_VARS} "'${GUID} ${USERS_BLOCK} ${NAMESPACES_BLOCK} ${CLEANUP_BLOCK}'
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
User mode: $USER_MODE
Users: $USER_DISPLAY
User password: $USER_PASSWORD

EOF
fi

echo -e "Credentials saved to: ${YELLOW}$CREDS_FILE${NC}"
echo -e "${RED}Do not commit credentials.txt to git.${NC}"
