#!/bin/bash

# Configuration script for Keycloak deployment
# This script helps configure required values for the deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Keycloak Configuration Helper ===${NC}\n"

# Function to prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    read -p "$(echo -e ${YELLOW}$prompt${NC}) [$default]: " input
    eval $var_name="${input:-$default}"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-16
}

echo "This script will help you configure the Keycloak deployment."
echo "Press Enter to accept default values or provide your own."
echo ""

# Deployment mode selection
echo -e "${GREEN}1. Deployment Mode${NC}"
echo "What components do you want to deploy?"
echo "  1) Infrastructure only (Keycloak operator, instance, PostgreSQL, realm, OAuth)"
echo "  2) Tenant only (Users, namespaces, RBAC - requires existing Keycloak)"
echo "  3) Both infrastructure and tenant (complete deployment)"
read -p "$(echo -e ${YELLOW}Choose option [1/2/3]:${NC}) " DEPLOY_MODE

case $DEPLOY_MODE in
    1)
        DEPLOY_INFRA="true"
        DEPLOY_TENANT="false"
        echo -e "${GREEN}Selected: Infrastructure only${NC}"
        ;;
    2)
        DEPLOY_INFRA="false"
        DEPLOY_TENANT="true"
        echo -e "${GREEN}Selected: Tenant only${NC}"
        ;;
    3)
        DEPLOY_INFRA="true"
        DEPLOY_TENANT="true"
        echo -e "${GREEN}Selected: Both infrastructure and tenant${NC}"
        ;;
    *)
        echo -e "${RED}Invalid option. Exiting.${NC}"
        exit 1
        ;;
esac

# Get Git repository URL
echo -e "\n${GREEN}2. Git Repository Configuration${NC}"
prompt_with_default "Enter your Git repository URL" "https://github.com/YOUR-ORG/YOUR-REPO.git" GIT_REPO
prompt_with_default "Enter the Git branch/tag" "main" GIT_BRANCH

# Get OpenShift ingress domain
echo -e "\n${GREEN}3. OpenShift Cluster Configuration${NC}"
if command -v oc &> /dev/null; then
    DETECTED_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo -e "${GREEN}Detected ingress domain: $DETECTED_DOMAIN${NC}"
        prompt_with_default "Use detected domain?" "y" USE_DETECTED
        if [ "$USE_DETECTED" = "y" ] || [ "$USE_DETECTED" = "Y" ]; then
            INGRESS_DOMAIN="$DETECTED_DOMAIN"
        else
            prompt_with_default "Enter OpenShift ingress domain" "apps.example.com" INGRESS_DOMAIN
        fi
    else
        prompt_with_default "Enter OpenShift ingress domain" "apps.example.com" INGRESS_DOMAIN
    fi
else
    prompt_with_default "Enter OpenShift ingress domain" "apps.example.com" INGRESS_DOMAIN
fi

# Password configuration
SECTION_NUM=4
if [ "$DEPLOY_INFRA" = "true" ] || [ "$DEPLOY_TENANT" = "true" ]; then
    echo -e "\n${GREEN}${SECTION_NUM}. Password Configuration${NC}"
    echo "Do you want to:"
    echo "  1) Generate random passwords (recommended)"
    echo "  2) Use the same password for all users (for testing only)"
    echo "  3) Set individual passwords"
    read -p "$(echo -e ${YELLOW}Choose option [1/2/3]:${NC}) " PASSWORD_OPTION

    case $PASSWORD_OPTION in
        1)
            if [ "$DEPLOY_INFRA" = "true" ]; then
                PG_PASSWORD=$(generate_password)
                OAUTH_SECRET=$(generate_password)
                ADMIN_PASSWORD=$(generate_password)
            fi
            if [ "$DEPLOY_TENANT" = "true" ]; then
                USER_PASSWORD=$(generate_password)
            fi
            echo -e "${GREEN}Generated random passwords${NC}"
            ;;
        2)
            prompt_with_default "Enter password to use for all users" "openshift" COMMON_PASSWORD
            if [ "$DEPLOY_INFRA" = "true" ]; then
                PG_PASSWORD="$COMMON_PASSWORD"
                OAUTH_SECRET=$(generate_password)  # Always generate random OAuth secret
                ADMIN_PASSWORD="$COMMON_PASSWORD"
            fi
            if [ "$DEPLOY_TENANT" = "true" ]; then
                USER_PASSWORD="$COMMON_PASSWORD"
            fi
            ;;
        3)
            if [ "$DEPLOY_INFRA" = "true" ]; then
                prompt_with_default "PostgreSQL password" "$(generate_password)" PG_PASSWORD
                prompt_with_default "OAuth client secret" "$(generate_password)" OAUTH_SECRET
                prompt_with_default "Admin user password" "openshift" ADMIN_PASSWORD
            fi
            if [ "$DEPLOY_TENANT" = "true" ]; then
                prompt_with_default "Regular users password" "openshift" USER_PASSWORD
            fi
            ;;
        *)
            echo -e "${RED}Invalid option. Exiting.${NC}"
            exit 1
            ;;
    esac
    SECTION_NUM=$((SECTION_NUM + 1))
fi

# User configuration (only for tenant deployments)
if [ "$DEPLOY_TENANT" = "true" ]; then
    echo -e "\n${GREEN}${SECTION_NUM}. User Configuration${NC}"
    prompt_with_default "Number of regular users to create" "5" NUM_USERS
    prompt_with_default "Username base for regular users" "user" USER_BASE
    SECTION_NUM=$((SECTION_NUM + 1))
fi

# Admin user configuration (only for infrastructure deployments)
if [ "$DEPLOY_INFRA" = "true" ]; then
    echo -e "\n${GREEN}${SECTION_NUM}. Admin User Configuration${NC}"
    prompt_with_default "Admin username" "admin" ADMIN_USER
    prompt_with_default "Create cluster-admin role binding for admin user? (y/n)" "y" CREATE_ADMIN

    if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
        ADMIN_ENABLED="true"
    else
        ADMIN_ENABLED="false"
    fi
    SECTION_NUM=$((SECTION_NUM + 1))
fi

# Additional options (only for infrastructure deployments)
if [ "$DEPLOY_INFRA" = "true" ]; then
    echo -e "\n${GREEN}${SECTION_NUM}. Additional Options${NC}"
    prompt_with_default "Remove kubeadmin user after OAuth is configured? (y/n)" "n" REMOVE_KUBEADMIN

    if [ "$REMOVE_KUBEADMIN" = "y" ] || [ "$REMOVE_KUBEADMIN" = "Y" ]; then
        REMOVE_KUBEADMIN_ENABLED="true"
        echo -e "${RED}WARNING: This will remove the kubeadmin user. Make sure OAuth works first!${NC}"
    else
        REMOVE_KUBEADMIN_ENABLED="false"
    fi
fi

# Confirm configuration
echo -e "\n${GREEN}=== Configuration Summary ===${NC}"

if [ "$DEPLOY_INFRA" = "true" ] && [ "$DEPLOY_TENANT" = "true" ]; then
    echo "Deployment Mode: Infrastructure + Tenant (Both)"
elif [ "$DEPLOY_INFRA" = "true" ]; then
    echo "Deployment Mode: Infrastructure Only"
else
    echo "Deployment Mode: Tenant Only"
fi

echo ""
echo "Git Repository: $GIT_REPO"
echo "Git Branch: $GIT_BRANCH"

if [ "$DEPLOY_INFRA" = "true" ]; then
    echo "Ingress Domain: $INGRESS_DOMAIN"
    echo "PostgreSQL Password: ${PG_PASSWORD:0:4}****"
    echo "OAuth Client Secret: ${OAUTH_SECRET:0:4}****"
    echo "Admin Username: $ADMIN_USER"
    echo "Admin Password: ${ADMIN_PASSWORD:0:4}****"
    echo "Create Admin ClusterRoleBinding: $ADMIN_ENABLED"
    echo "Remove Kubeadmin: $REMOVE_KUBEADMIN_ENABLED"
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    echo "Regular Users: ${USER_BASE}1..${USER_BASE}${NUM_USERS}"
    echo "Users Password: ${USER_PASSWORD:0:4}****"
fi

echo ""

read -p "$(echo -e ${YELLOW}Apply this configuration? [y/N]:${NC}) " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Configuration cancelled."
    exit 0
fi

# Apply configuration
echo -e "\n${GREEN}Applying configuration...${NC}"

# Update Git repository URLs in app manifests
if [ "$DEPLOY_INFRA" = "true" ]; then
    echo "Updating infrastructure app manifests..."
    for app_file in infra/apps/*.yaml; do
        if [ -f "$app_file" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
                sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
            else
                sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
                sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
            fi
        fi
    done
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    echo "Updating tenant app manifests..."
    for app_file in tenant/apps/*.yaml; do
        if [ -f "$app_file" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
                sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
            else
                sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
                sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
            fi
        fi
    done
fi

# Update parent apps
echo "Updating parent app manifests..."
if [ "$DEPLOY_INFRA" = "true" ] && [ -f "infra/parent-app.yaml" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "infra/parent-app.yaml"
        sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "infra/parent-app.yaml"
    else
        sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "infra/parent-app.yaml"
        sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "infra/parent-app.yaml"
    fi
fi

if [ "$DEPLOY_TENANT" = "true" ] && [ -f "tenant/parent-app.yaml" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "tenant/parent-app.yaml"
        sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "tenant/parent-app.yaml"
    else
        sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "tenant/parent-app.yaml"
        sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "tenant/parent-app.yaml"
    fi
fi

if [ "$DEPLOY_INFRA" = "true" ] && [ "$DEPLOY_TENANT" = "true" ] && [ -f "platform-parent-app.yaml" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "platform-parent-app.yaml"
        sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "platform-parent-app.yaml"
    else
        sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "platform-parent-app.yaml"
        sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "platform-parent-app.yaml"
    fi
fi

# Infrastructure-specific configuration
if [ "$DEPLOY_INFRA" = "true" ]; then
    echo "Configuring infrastructure chart values..."

    # Update ingress domain
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" infra/charts/keycloak-instance/values.yaml
        sed -i '' "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" infra/charts/keycloak-oauth/values.yaml
    else
        sed -i "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" infra/charts/keycloak-instance/values.yaml
        sed -i "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" infra/charts/keycloak-oauth/values.yaml
    fi

    # Update PostgreSQL password
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|password: changeme123|password: $PG_PASSWORD|g" infra/charts/keycloak-postgres/values.yaml
    else
        sed -i "s|password: changeme123|password: $PG_PASSWORD|g" infra/charts/keycloak-postgres/values.yaml
    fi

    # Update OAuth secret
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|secret: changeme123|secret: $OAUTH_SECRET|g" infra/charts/keycloak-realm/values.yaml
        sed -i '' "s|secret: changeme123|secret: $OAUTH_SECRET|g" infra/charts/keycloak-oauth/values.yaml
    else
        sed -i "s|secret: changeme123|secret: $OAUTH_SECRET|g" infra/charts/keycloak-realm/values.yaml
        sed -i "s|secret: changeme123|secret: $OAUTH_SECRET|g" infra/charts/keycloak-oauth/values.yaml
    fi

    # Update admin user
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|username: admin|username: $ADMIN_USER|g" infra/charts/keycloak-realm/values.yaml
        sed -i '' "s|username: admin|username: $ADMIN_USER|g" infra/charts/keycloak-oauth/values.yaml
        sed -i '' "/users:/,/admin:/{s|password: changeme123|password: $ADMIN_PASSWORD|;}" infra/charts/keycloak-realm/values.yaml
        sed -i '' "s|enabled: true  # Disable admin user creation|enabled: $ADMIN_ENABLED|g" infra/charts/keycloak-realm/values.yaml
        sed -i '' "s|enabled: true$|enabled: $ADMIN_ENABLED|g" infra/charts/keycloak-oauth/values.yaml
    else
        sed -i "s|username: admin|username: $ADMIN_USER|g" infra/charts/keycloak-realm/values.yaml
        sed -i "s|username: admin|username: $ADMIN_USER|g" infra/charts/keycloak-oauth/values.yaml
        sed -i "/users:/,/admin:/{s|password: changeme123|password: $ADMIN_PASSWORD|;}" infra/charts/keycloak-realm/values.yaml
        sed -i "s|enabled: true  # Disable admin user creation|enabled: $ADMIN_ENABLED|g" infra/charts/keycloak-realm/values.yaml
        sed -i "s|enabled: true$|enabled: $ADMIN_ENABLED|g" infra/charts/keycloak-oauth/values.yaml
    fi

    # Update regular users (in realm - for infra mode, these are created in Keycloak)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|count: 5|count: 0|g" infra/charts/keycloak-realm/values.yaml
        sed -i '' "s|usernameBase: user|usernameBase: $USER_BASE|g" infra/charts/keycloak-realm/values.yaml
    else
        sed -i "s|count: 5|count: 0|g" infra/charts/keycloak-realm/values.yaml
        sed -i "s|usernameBase: user|usernameBase: $USER_BASE|g" infra/charts/keycloak-realm/values.yaml
    fi

    # Update kubeadmin removal
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|enabled: false  # Enable to remove kubeadmin user|enabled: $REMOVE_KUBEADMIN_ENABLED|g" infra/charts/keycloak-oauth/values.yaml
    else
        sed -i "s|enabled: false  # Enable to remove kubeadmin user|enabled: $REMOVE_KUBEADMIN_ENABLED|g" infra/charts/keycloak-oauth/values.yaml
    fi
fi

# Tenant-specific configuration
if [ "$DEPLOY_TENANT" = "true" ]; then
    echo "Configuring tenant chart values..."

    # Note: Tenant user configuration would go in tenant/charts/keycloak-users/values.yaml
    # This is typically done via separate tenant values files, not this script
    # For now, we just ensure the Git repo is updated above
fi

echo -e "${GREEN}Configuration applied successfully!${NC}\n"

# Save credentials to a file
CREDS_FILE="credentials.txt"
cat > "$CREDS_FILE" <<EOF
Keycloak Deployment Credentials
================================

Generated: $(date)
Deployment Mode: $([ "$DEPLOY_INFRA" = "true" ] && [ "$DEPLOY_TENANT" = "true" ] && echo "Infrastructure + Tenant" || ([ "$DEPLOY_INFRA" = "true" ] && echo "Infrastructure Only" || echo "Tenant Only"))

EOF

if [ "$DEPLOY_INFRA" = "true" ]; then
    cat >> "$CREDS_FILE" <<EOF
OpenShift Ingress Domain: $INGRESS_DOMAIN
Keycloak Console URL: https://sso.$INGRESS_DOMAIN

PostgreSQL Database:
  Password: $PG_PASSWORD

OAuth Client:
  Client ID: idp-4-ocp
  Client Secret: $OAUTH_SECRET

Admin User (Cluster Admin):
  Username: $ADMIN_USER
  Password: $ADMIN_PASSWORD

EOF
fi

if [ "$DEPLOY_TENANT" = "true" ]; then
    cat >> "$CREDS_FILE" <<EOF
Regular Users:
  Usernames: ${USER_BASE}1 through ${USER_BASE}${NUM_USERS}
  Password: $USER_PASSWORD

EOF
fi

echo -e "${GREEN}Credentials saved to: $CREDS_FILE${NC}"
echo -e "${RED}IMPORTANT: Keep this file secure and do not commit it to Git!${NC}\n"

echo -e "${GREEN}Next steps:${NC}"
echo "1. Review the configuration in the chart values files:"

if [ "$DEPLOY_INFRA" = "true" ]; then
    echo "   - infra/charts/*/values.yaml"
fi
if [ "$DEPLOY_TENANT" = "true" ]; then
    echo "   - tenant/charts/*/values.yaml"
fi

echo ""
echo "2. Commit and push changes to your Git repository:"

if [ "$DEPLOY_INFRA" = "true" ] && [ "$DEPLOY_TENANT" = "true" ]; then
    echo "   git add infra/ tenant/ platform-parent-app.yaml"
elif [ "$DEPLOY_INFRA" = "true" ]; then
    echo "   git add infra/"
else
    echo "   git add tenant/"
fi

echo "   git commit -m 'Configure Keycloak deployment'"
echo "   git push"
echo ""

if [ "$DEPLOY_INFRA" = "true" ] && [ "$DEPLOY_TENANT" = "true" ]; then
    echo "3. Deploy the complete platform:"
    echo "   oc apply -f platform-parent-app.yaml"
    echo ""
    echo "   Or deploy individually:"
    echo "   oc apply -f infra/parent-app.yaml"
    echo "   oc apply -f tenant/parent-app.yaml"
elif [ "$DEPLOY_INFRA" = "true" ]; then
    echo "3. Deploy the infrastructure:"
    echo "   oc apply -f infra/parent-app.yaml"
    echo ""
    echo "   This will deploy:"
    echo "   - Keycloak operator"
    echo "   - PostgreSQL database"
    echo "   - Keycloak instance"
    echo "   - Keycloak realm configuration"
    echo "   - OpenShift OAuth integration"
else
    echo "3. Deploy the tenant resources:"
    echo "   oc apply -f tenant/parent-app.yaml"
    echo ""
    echo "   This will deploy:"
    echo "   - Keycloak users"
    echo "   - Namespaces for users"
    echo "   - RBAC bindings"
    echo ""
    echo "   NOTE: Make sure Keycloak infrastructure is already deployed!"
fi

echo ""
if [ "$DEPLOY_INFRA" = "true" ]; then
    echo "For more information, see infra/README.md"
fi
if [ "$DEPLOY_TENANT" = "true" ]; then
    echo "For tenant configuration, see tenant/README.md"
fi
