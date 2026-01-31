#!/bin/bash

# Configuration script for Keycloak ArgoCD deployment
# This script helps configure required values for the deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Keycloak ArgoCD Configuration Helper ===${NC}\n"

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

# Get Git repository URL
echo -e "${GREEN}1. Git Repository Configuration${NC}"
prompt_with_default "Enter your Git repository URL" "https://github.com/YOUR-ORG/YOUR-REPO.git" GIT_REPO
prompt_with_default "Enter the Git branch/tag" "main" GIT_BRANCH

# Get OpenShift ingress domain
echo -e "\n${GREEN}2. OpenShift Cluster Configuration${NC}"
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
echo -e "\n${GREEN}3. Password Configuration${NC}"
echo "Do you want to:"
echo "  1) Generate random passwords (recommended)"
echo "  2) Use the same password for all users (for testing only)"
echo "  3) Set individual passwords"
read -p "$(echo -e ${YELLOW}Choose option [1/2/3]:${NC}) " PASSWORD_OPTION

case $PASSWORD_OPTION in
    1)
        PG_PASSWORD=$(generate_password)
        OAUTH_SECRET=$(generate_password)
        ADMIN_PASSWORD=$(generate_password)
        USER_PASSWORD=$(generate_password)
        echo -e "${GREEN}Generated random passwords${NC}"
        ;;
    2)
        prompt_with_default "Enter password to use for all users" "openshift" COMMON_PASSWORD
        PG_PASSWORD="$COMMON_PASSWORD"
        OAUTH_SECRET=$(generate_password)  # Always generate random OAuth secret
        ADMIN_PASSWORD="$COMMON_PASSWORD"
        USER_PASSWORD="$COMMON_PASSWORD"
        ;;
    3)
        prompt_with_default "PostgreSQL password" "$(generate_password)" PG_PASSWORD
        prompt_with_default "OAuth client secret" "$(generate_password)" OAUTH_SECRET
        prompt_with_default "Admin user password" "openshift" ADMIN_PASSWORD
        prompt_with_default "Regular users password" "openshift" USER_PASSWORD
        ;;
    *)
        echo -e "${RED}Invalid option. Exiting.${NC}"
        exit 1
        ;;
esac

# User configuration
echo -e "\n${GREEN}4. User Configuration${NC}"
prompt_with_default "Number of regular users to create" "5" NUM_USERS
prompt_with_default "Username base for regular users" "user" USER_BASE
prompt_with_default "Admin username" "admin" ADMIN_USER
prompt_with_default "Create cluster-admin role binding for admin user? (y/n)" "y" CREATE_ADMIN

if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
    ADMIN_ENABLED="true"
else
    ADMIN_ENABLED="false"
fi

# Additional options
echo -e "\n${GREEN}5. Additional Options${NC}"
prompt_with_default "Remove kubeadmin user after OAuth is configured? (y/n)" "n" REMOVE_KUBEADMIN

if [ "$REMOVE_KUBEADMIN" = "y" ] || [ "$REMOVE_KUBEADMIN" = "Y" ]; then
    REMOVE_KUBEADMIN_ENABLED="true"
    echo -e "${RED}WARNING: This will remove the kubeadmin user. Make sure OAuth works first!${NC}"
else
    REMOVE_KUBEADMIN_ENABLED="false"
fi

# Confirm configuration
echo -e "\n${GREEN}=== Configuration Summary ===${NC}"
echo "Git Repository: $GIT_REPO"
echo "Git Branch: $GIT_BRANCH"
echo "Ingress Domain: $INGRESS_DOMAIN"
echo "PostgreSQL Password: ${PG_PASSWORD:0:4}****"
echo "OAuth Client Secret: ${OAUTH_SECRET:0:4}****"
echo "Admin Username: $ADMIN_USER"
echo "Admin Password: ${ADMIN_PASSWORD:0:4}****"
echo "Regular Users: ${USER_BASE}1..${USER_BASE}${NUM_USERS}"
echo "Users Password: ${USER_PASSWORD:0:4}****"
echo "Create Admin ClusterRoleBinding: $ADMIN_ENABLED"
echo "Remove Kubeadmin: $REMOVE_KUBEADMIN_ENABLED"
echo ""

read -p "$(echo -e ${YELLOW}Apply this configuration? [y/N]:${NC}) " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Configuration cancelled."
    exit 0
fi

# Apply configuration
echo -e "\n${GREEN}Applying configuration...${NC}"

# Update Git repository URLs in all app manifests
for app_file in apps/*.yaml; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
        sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
    else
        sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" "$app_file"
        sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" "$app_file"
    fi
done

# Update parent app
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|repoURL: .*|repoURL: $GIT_REPO|g" parent-app.yaml
    sed -i '' "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" parent-app.yaml
else
    sed -i "s|repoURL: .*|repoURL: $GIT_REPO|g" parent-app.yaml
    sed -i "s|targetRevision: .*|targetRevision: $GIT_BRANCH|g" parent-app.yaml
fi

# Update ingress domain
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" charts/keycloak-instance/values.yaml
    sed -i '' "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" charts/keycloak-oauth/values.yaml
else
    sed -i "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" charts/keycloak-instance/values.yaml
    sed -i "s|ingressDomain: .*|ingressDomain: $INGRESS_DOMAIN|g" charts/keycloak-oauth/values.yaml
fi

# Update PostgreSQL password
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|password: changeme123|password: $PG_PASSWORD|g" charts/keycloak-postgres/values.yaml
else
    sed -i "s|password: changeme123|password: $PG_PASSWORD|g" charts/keycloak-postgres/values.yaml
fi

# Update OAuth secret
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|secret: changeme123|secret: $OAUTH_SECRET|g" charts/keycloak-realm/values.yaml
    sed -i '' "s|secret: changeme123|secret: $OAUTH_SECRET|g" charts/keycloak-oauth/values.yaml
else
    sed -i "s|secret: changeme123|secret: $OAUTH_SECRET|g" charts/keycloak-realm/values.yaml
    sed -i "s|secret: changeme123|secret: $OAUTH_SECRET|g" charts/keycloak-oauth/values.yaml
fi

# Update admin user
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|username: admin|username: $ADMIN_USER|g" charts/keycloak-realm/values.yaml
    sed -i '' "s|username: admin|username: $ADMIN_USER|g" charts/keycloak-oauth/values.yaml
    sed -i '' "/users:/,/admin:/{s|password: changeme123|password: $ADMIN_PASSWORD|;}" charts/keycloak-realm/values.yaml
    sed -i '' "s|enabled: true  # Disable admin user creation|enabled: $ADMIN_ENABLED|g" charts/keycloak-realm/values.yaml
    sed -i '' "s|enabled: true$|enabled: $ADMIN_ENABLED|g" charts/keycloak-oauth/values.yaml
else
    sed -i "s|username: admin|username: $ADMIN_USER|g" charts/keycloak-realm/values.yaml
    sed -i "s|username: admin|username: $ADMIN_USER|g" charts/keycloak-oauth/values.yaml
    sed -i "/users:/,/admin:/{s|password: changeme123|password: $ADMIN_PASSWORD|;}" charts/keycloak-realm/values.yaml
    sed -i "s|enabled: true  # Disable admin user creation|enabled: $ADMIN_ENABLED|g" charts/keycloak-realm/values.yaml
    sed -i "s|enabled: true$|enabled: $ADMIN_ENABLED|g" charts/keycloak-oauth/values.yaml
fi

# Update regular users
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|count: 5|count: $NUM_USERS|g" charts/keycloak-realm/values.yaml
    sed -i '' "s|usernameBase: user|usernameBase: $USER_BASE|g" charts/keycloak-realm/values.yaml
    sed -i '' "/regular:/,/realmRoles:/{s|password: changeme123|password: $USER_PASSWORD|;}" charts/keycloak-realm/values.yaml
else
    sed -i "s|count: 5|count: $NUM_USERS|g" charts/keycloak-realm/values.yaml
    sed -i "s|usernameBase: user|usernameBase: $USER_BASE|g" charts/keycloak-realm/values.yaml
    sed -i "/regular:/,/realmRoles:/{s|password: changeme123|password: $USER_PASSWORD|;}" charts/keycloak-realm/values.yaml
fi

# Update kubeadmin removal
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|enabled: false  # Enable to remove kubeadmin user|enabled: $REMOVE_KUBEADMIN_ENABLED|g" charts/keycloak-oauth/values.yaml
else
    sed -i "s|enabled: false  # Enable to remove kubeadmin user|enabled: $REMOVE_KUBEADMIN_ENABLED|g" charts/keycloak-oauth/values.yaml
fi

echo -e "${GREEN}Configuration applied successfully!${NC}\n"

# Save credentials to a file
CREDS_FILE="credentials.txt"
cat > "$CREDS_FILE" <<EOF
Keycloak Deployment Credentials
================================

Generated: $(date)

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

Regular Users:
  Usernames: ${USER_BASE}1 through ${USER_BASE}${NUM_USERS}
  Password: $USER_PASSWORD

EOF

echo -e "${GREEN}Credentials saved to: $CREDS_FILE${NC}"
echo -e "${RED}IMPORTANT: Keep this file secure and do not commit it to Git!${NC}\n"

echo -e "${GREEN}Next steps:${NC}"
echo "1. Review the configuration in the chart values files"
echo "2. Commit and push changes to your Git repository:"
echo "   git add argocd/"
echo "   git commit -m 'Configure Keycloak ArgoCD deployment'"
echo "   git push"
echo "3. Deploy the parent application:"
echo "   oc apply -f argocd/parent-app.yaml"
echo ""
echo "For more information, see argocd/README.md"
