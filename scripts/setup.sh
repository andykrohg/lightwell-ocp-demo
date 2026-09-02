#!/bin/bash
set -euo pipefail

NAMESPACE="${DEMO_NAMESPACE:-lightwell-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

banner() {
  echo -e "\n${CYAN}========================================${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}========================================${NC}\n"
}

check_var() {
  if [ -z "${!1:-}" ]; then
    echo -e "${RED}ERROR: $1 is not set${NC}"
    echo "  Export it before running: export $1=<value>"
    exit 1
  fi
}

banner "Lightwell Demo — Setup"

echo "Checking required environment variables..."
check_var ROX_API_TOKEN
check_var ROX_CENTRAL_ENDPOINT
check_var TPA_URL
check_var TPA_CLIENT_ID
check_var TPA_CLIENT_SECRET
check_var TPA_OIDC_ISSUER
echo -e "${GREEN}All required variables set.${NC}"

echo ""
echo "Optional variables (will use defaults if unset):"
echo "  LIGHTWELL_USERNAME  = ${LIGHTWELL_USERNAME:-(not set, Lightwell repo won't be configured)}"
echo "  LIGHTWELL_PASSWORD  = ${LIGHTWELL_PASSWORD:+(set)}"
echo "  DEMO_NAMESPACE      = ${NAMESPACE}"
echo ""

banner "Step 1: Create OpenShift project"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"

banner "Step 2: Create secrets"

oc create secret generic acs-credentials \
  --from-literal=rox-api-token="${ROX_API_TOKEN}" \
  --from-literal=rox-central-endpoint="${ROX_CENTRAL_ENDPOINT}" \
  --dry-run=client -o yaml | oc apply -f -

oc create secret generic tpa-credentials \
  --from-literal=client-id="${TPA_CLIENT_ID}" \
  --from-literal=client-secret="${TPA_CLIENT_SECRET}" \
  --from-literal=oidc-issuer="${TPA_OIDC_ISSUER}" \
  --dry-run=client -o yaml | oc apply -f -

if [ -n "${LIGHTWELL_USERNAME:-}" ] && [ -n "${LIGHTWELL_PASSWORD:-}" ]; then
  envsubst < "$PROJECT_DIR/catalog-app/settings.xml.template" > /tmp/lightwell-settings.xml
  oc create secret generic maven-settings \
    --from-file=settings.xml=/tmp/lightwell-settings.xml \
    --dry-run=client -o yaml | oc apply -f -
  rm -f /tmp/lightwell-settings.xml
  echo -e "${GREEN}Maven settings secret created with Lightwell credentials.${NC}"
else
  echo -e "${YELLOW}Skipping Lightwell Maven settings (credentials not provided).${NC}"
fi

banner "Step 3: Create pipeline workspace PVC"
oc apply -f "$PROJECT_DIR/tekton/workspace-pvc.yaml"

banner "Step 4: Install Tekton tasks"
oc apply -f "$PROJECT_DIR/tekton/tasks/"

banner "Step 5: Install Tekton pipeline"
oc apply -f "$PROJECT_DIR/tekton/pipeline.yaml"

banner "Step 6: Import ACS policies"
for policy in "$PROJECT_DIR"/acs-policies/*.json; do
  policy_name=$(jq -r .name "$policy")
  echo -n "  Importing: $policy_name ... "
  response=$(curl -sk -X POST "https://${ROX_CENTRAL_ENDPOINT}/v1/policies" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @"$policy" -w "%{http_code}" -o /dev/null 2>/dev/null) || true
  if [ "$response" = "200" ] || [ "$response" = "201" ]; then
    echo -e "${GREEN}OK${NC}"
  elif [ "$response" = "409" ]; then
    echo -e "${YELLOW}Already exists${NC}"
  else
    echo -e "${YELLOW}HTTP $response (may already exist)${NC}"
  fi
done

banner "Step 7: Grant pipeline service account permissions"
oc adm policy add-role-to-user edit system:serviceaccount:"$NAMESPACE":pipeline 2>/dev/null || true

banner "Step 8: Deploy demo hub"
oc apply -k "$PROJECT_DIR/manifests/overlays/dashboard/"

banner "Setup Complete"
echo ""
HUB_URL=$(oc get route demo-hub -o jsonpath='{.spec.host}' 2>/dev/null || echo "<pending>")
echo -e "Demo Hub: ${GREEN}https://${HUB_URL}${NC}"
echo ""
echo "Next steps:"
echo "  1. Run 'make demo' or './scripts/demo.sh' to start the guided demo"
echo "  2. Or trigger pipelines manually:"
echo "     make pipeline-vulnerable"
echo "     make pipeline-remediated"
