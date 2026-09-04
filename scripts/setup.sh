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
echo "  REGISTRY_HOST         = ${REGISTRY_HOST}"
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

if ! oc get secret cosign-signing-key -n "$DEMO_NAMESPACE" &>/dev/null; then
  echo "  Generating cosign key pair..."
  COSIGN_PASSWORD="" cosign generate-key-pair k8s://"$DEMO_NAMESPACE"/cosign-signing-key 2>/dev/null
  echo -e "  ${GREEN}Cosign key pair created${NC}"
else
  echo -e "  Cosign signing key ${YELLOW}already exists${NC}"
fi

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

banner "Step 5: Configure ACS integrations and policies"

echo -n "  Registering in-cluster registry... "
REG_RESPONSE=$(curl -sk -X POST "https://${ROX_CENTRAL_ENDPOINT}/v1/imageintegrations" \
  -H "Authorization: Bearer ${ROX_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Lightwell Demo Registry\",
    \"type\": \"docker\",
    \"categories\": [\"REGISTRY\"],
    \"docker\": {
      \"endpoint\": \"${REGISTRY_HOST}\",
      \"insecure\": false
    },
    \"skipTestIntegration\": true
  }" -w "%{http_code}" -o /dev/null 2>/dev/null) || true
if [ "$REG_RESPONSE" = "200" ] || [ "$REG_RESPONSE" = "201" ]; then
  echo -e "${GREEN}OK${NC}"
elif [ "$REG_RESPONSE" = "409" ]; then
  echo -e "${YELLOW}already exists${NC}"
else
  echo -e "${YELLOW}HTTP $REG_RESPONSE (may already exist)${NC}"
fi

echo -n "  Creating cosign signature integration... "
COSIGN_PUB=$(oc get secret cosign-signing-key -n "$DEMO_NAMESPACE" -o jsonpath='{.data.cosign\.pub}' 2>/dev/null | base64 -d)
SIG_RESPONSE=$(COSIGN_PUB="$COSIGN_PUB" python3 -c "
import json, os
pub = os.environ['COSIGN_PUB']
print(json.dumps({'name':'Lightwell Demo Cosign','cosign':{'publicKeys':[{'name':'demo-signing-key','publicKeyPemEnc':pub}]}}))
" | curl -sk -X POST "https://${ROX_CENTRAL_ENDPOINT}/v1/signatureintegrations" \
  -H "Authorization: Bearer ${ROX_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @- 2>/dev/null)
SIG_ID=$(echo "$SIG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null) || true
if [ -n "$SIG_ID" ]; then
  echo -e "${GREEN}OK${NC} ($SIG_ID)"
else
  SIG_ID=$(curl -sk "https://${ROX_CENTRAL_ENDPOINT}/v1/signatureintegrations" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" 2>/dev/null \
    | python3 -c "import sys,json; [print(i['id']) for i in json.load(sys.stdin).get('integrations',[]) if i['name']=='Lightwell Demo Cosign']" 2>/dev/null) || true
  if [ -n "$SIG_ID" ]; then
    echo -e "${YELLOW}already exists${NC} ($SIG_ID)"
  else
    echo -e "${YELLOW}failed — signature policy will not work${NC}"
  fi
fi

echo "  Importing policies (delete + recreate for idempotency)..."
EXISTING_POLICIES=$(curl -sk "https://${ROX_CENTRAL_ENDPOINT}/v1/policies" \
  -H "Authorization: Bearer ${ROX_API_TOKEN}" 2>/dev/null)

import_policy() {
  local policy_file="$1"
  local policy_json="$2"
  local policy_name
  policy_name=$(echo "$policy_json" | jq -r .name)
  echo -n "    $policy_name ... "

  OLD_ID=$(echo "$EXISTING_POLICIES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('policies', []):
    if p['name'] == '$policy_name':
        print(p['id'])
        break
" 2>/dev/null) || true

  if [ -n "$OLD_ID" ]; then
    curl -sk -X DELETE "https://${ROX_CENTRAL_ENDPOINT}/v1/policies/${OLD_ID}" \
      -H "Authorization: Bearer ${ROX_API_TOKEN}" -o /dev/null 2>/dev/null || true
  fi

  response=$(curl -sk -X POST "https://${ROX_CENTRAL_ENDPOINT}/v1/policies" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$policy_json" -w "%{http_code}" -o /dev/null 2>/dev/null) || true
  if [ "$response" = "200" ] || [ "$response" = "201" ]; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${YELLOW}HTTP $response${NC}"
  fi
}

for policy in "$PROJECT_DIR"/acs-policies/*.json; do
  if [ "$(basename "$policy")" = "require-signature.json" ] && [ -n "$SIG_ID" ]; then
    POLICY_JSON=$(jq --arg sig_id "$SIG_ID" \
      '.policySections[0].policyGroups[0].values[0].value = $sig_id' "$policy")
    import_policy "$policy" "$POLICY_JSON"
  else
    import_policy "$policy" "$(cat "$policy")"
  fi
done

banner "Step 6: Upload Lightwell VEX data to TPA"

echo -n "  Obtaining OIDC token... "
TPA_TOKEN=$(curl -sf -X POST "${TPA_OIDC_ISSUER_URL}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${TPA_CLIENT_ID}" \
  -d "client_secret=${TPA_CLIENT_SECRET}" \
  -d "scope=openid" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null) || true
if [ -n "$TPA_TOKEN" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${YELLOW}failed — VEX upload will be skipped${NC}"
fi

if [ -n "$TPA_TOKEN" ]; then
  echo -n "  Uploading Lightwell VEX document... "
  VEX_RESPONSE=$(curl -sk -X POST "${TPA_URL}/api/v3/advisory?format=csaf" \
    -H "Authorization: Bearer $TPA_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @"$PROJECT_DIR/vex/lightwell-remediated.json" \
    -w "%{http_code}" -o /dev/null 2>/dev/null) || true
  if [ "$VEX_RESPONSE" -ge 200 ] 2>/dev/null && [ "$VEX_RESPONSE" -lt 300 ] 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${YELLOW}HTTP $VEX_RESPONSE${NC}"
  fi
fi

banner "Step 7: Grant pipeline service account permissions"
oc adm policy add-role-to-user edit system:serviceaccount:"$DEMO_NAMESPACE":pipeline 2>/dev/null || true
oc adm policy add-scc-to-user privileged system:serviceaccount:"$DEMO_NAMESPACE":pipeline 2>/dev/null || true

banner "Step 8: Deploy in-cluster container registry"
oc apply -f "$PROJECT_DIR/manifests/base/registry/"
echo "  Waiting for registry to be ready..."
oc rollout status deployment/registry -n "$DEMO_NAMESPACE" --timeout=60s

banner "Step 9: Deploy catalog apps"
kustomize build "$PROJECT_DIR/manifests/overlays/vulnerable" \
  | sed -e "s|__REGISTRY_HOST__|${REGISTRY_HOST}|g" \
  | oc apply -n "$DEMO_NAMESPACE" -f -
kustomize build "$PROJECT_DIR/manifests/overlays/remediated" \
  | sed -e "s|__REGISTRY_HOST__|${REGISTRY_HOST}|g" \
  | oc apply -n "$DEMO_NAMESPACE" -f -

banner "Step 10: Deploy demo hub"
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
