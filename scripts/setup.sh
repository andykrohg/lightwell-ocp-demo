#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-env.sh"

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

banner "Lightwell Demo — Setup"

if [ -z "$ROX_API_TOKEN" ]; then
  echo -e "${RED}ERROR: ROX_API_TOKEN is not set${NC}"
  echo "  Set it in demo.env or export it before running."
  echo "  Generate one in ACS Central -> Platform Configuration -> Integrations -> API Token"
  exit 1
fi

echo "  DEMO_NAMESPACE        = ${DEMO_NAMESPACE}"
echo "  TPA_NAMESPACE         = ${TPA_NAMESPACE}"
echo "  APPS_DOMAIN           = ${APPS_DOMAIN}"
echo "  TPA_URL               = ${TPA_URL}"
echo "  ROX_CENTRAL_ENDPOINT  = ${ROX_CENTRAL_ENDPOINT}"
echo "  ACS_CONSOLE_URL       = ${ACS_CONSOLE_URL}"
echo "  OCP_CONSOLE_URL       = ${OCP_CONSOLE_URL}"
echo ""

banner "Step 1: Create OpenShift project"
oc new-project "$DEMO_NAMESPACE" 2>/dev/null || oc project "$DEMO_NAMESPACE"

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

banner "Step 3: Create pipeline workspace PVC"
oc apply -f "$PROJECT_DIR/tekton/workspace-pvc.yaml"

banner "Step 4: Install Tekton tasks and pipeline"
echo "  Installing standard tasks from Tekton catalog..."
oc apply -n "$DEMO_NAMESPACE" -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
oc apply -n "$DEMO_NAMESPACE" -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/maven/0.3/maven.yaml
oc apply -n "$DEMO_NAMESPACE" -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.8/buildah.yaml
echo "  Installing custom tasks..."
oc apply -f "$PROJECT_DIR/tekton/tasks/"
oc apply -f "$PROJECT_DIR/tekton/pipeline.yaml"

banner "Step 5: Import ACS policies"
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

banner "Step 6: Grant pipeline service account permissions"
oc adm policy add-role-to-user edit system:serviceaccount:"$DEMO_NAMESPACE":pipeline 2>/dev/null || true
oc adm policy add-scc-to-user privileged system:serviceaccount:"$DEMO_NAMESPACE":pipeline 2>/dev/null || true

banner "Step 7: Deploy catalog apps"
oc apply -k "$PROJECT_DIR/manifests/overlays/vulnerable/"
oc apply -k "$PROJECT_DIR/manifests/overlays/remediated/"

banner "Step 8: Deploy demo hub"
kustomize build "$PROJECT_DIR/manifests/overlays/dashboard" \
  | sed \
    -e "s|__TPA_CONSOLE_URL__|${TPA_CONSOLE_URL}|g" \
    -e "s|__ACS_CONSOLE_URL__|${ACS_CONSOLE_URL}|g" \
    -e "s|__OCP_CONSOLE_URL__|${OCP_CONSOLE_URL}|g" \
    -e "s|__DEMO_NAMESPACE__|${DEMO_NAMESPACE}|g" \
  | oc apply -n "$DEMO_NAMESPACE" -f -

banner "Setup Complete"
echo ""
HUB_URL=$(oc get route demo-hub -n "$DEMO_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "<pending>")
echo -e "Demo Hub:     ${GREEN}https://${HUB_URL}${NC}"
echo -e "TPA Console:  ${GREEN}${TPA_CONSOLE_URL}${NC}"
echo -e "ACS Console:  ${GREEN}${ACS_CONSOLE_URL}${NC}"
echo -e "OCP Console:  ${GREEN}${OCP_CONSOLE_URL}${NC}"
echo ""
echo "Next steps:"
echo "  1. Run 'make demo' or './scripts/demo.sh' to start the guided demo"
echo "  2. Or trigger pipelines manually:"
echo "     make pipeline-vulnerable"
echo "     make pipeline-remediated"
