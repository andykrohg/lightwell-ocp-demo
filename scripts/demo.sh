#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-env.sh"

NAMESPACE="$DEMO_NAMESPACE"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  echo -e "\n${CYAN}======================================================${NC}"
  echo -e "${CYAN}  ${BOLD}$1${NC}"
  echo -e "${CYAN}======================================================${NC}\n"
}

narrate() {
  echo -e "${YELLOW}$1${NC}"
}

pause() {
  echo ""
  echo -e "${GREEN}>>> Press ENTER to continue...${NC}"
  read -r
  echo ""
}

sed_pipelinerun() {
  sed \
    -e "s|__DEMO_NAMESPACE__|${DEMO_NAMESPACE}|g" \
    -e "s|__REGISTRY_HOST__|${REGISTRY_HOST}|g" \
    -e "s|__TPA_URL__|${TPA_URL}|g" \
    -e "s|__TPA_OIDC_ISSUER_URL__|${TPA_OIDC_ISSUER_URL}|g" \
    -e "s|__TPA_CLIENT_SECRET__|${TPA_CLIENT_SECRET}|g" \
    -e "s|__ROX_CENTRAL_ENDPOINT__|${ROX_CENTRAL_ENDPOINT}|g" \
    -e "s|__ROX_API_TOKEN__|${ROX_API_TOKEN}|g" \
    "$1"
}

HUB_URL=$(oc get route demo-hub -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
ACS_URL="${ACS_CONSOLE_URL#https://}"
TPA_URL_HOST="${TPA_CONSOLE_URL#https://}"
OCP_URL="$OCP_CONSOLE_URL"

clear
echo -e "${BOLD}"
echo "  ╦  ╦╔═╗╦ ╦╔╦╗╦ ╦╔═╗╦  ╦    ╔╦╗╔═╗╔╦╗╔═╗"
echo "  ║  ║║ ╦╠═╣ ║ ║║║║╣ ║  ║     ║║║╣ ║║║║ ║"
echo "  ╩═╝╩╚═╝╩ ╩ ╩ ╚╩╝╚═╝╩═╝╩═╝  ═╩╝╚═╝╩ ╩╚═╝"
echo ""
echo "  From Vulnerable to Verified"
echo -e "${NC}"
echo ""
narrate "This demo walks through three acts:"
echo "  1. The Problem  — Examine a vulnerable app and what security tools see"
echo "  2. The Fix      — Rebuild with Lightwell Network and compare results"
echo "  3. Lock the Door — Enable enforcement to block vulnerable builds"
echo ""
[ -n "$HUB_URL" ] && echo -e "  Demo Hub:  ${GREEN}https://${HUB_URL}${NC}"
[ -n "$TPA_URL_HOST" ] && echo -e "  TPA:       ${GREEN}https://${TPA_URL_HOST}${NC}"
[ -n "$ACS_URL" ] && echo -e "  ACS:       ${GREEN}https://${ACS_URL}${NC}"
[ -n "$OCP_URL" ] && echo -e "  OpenShift: ${GREEN}${OCP_URL}${NC}"
pause

# ─── ACT 1 ────────────────────────────────────────────────

banner "ACT 1: THE PROBLEM"

narrate "We have a catalog microservice built with standard Maven Central dependencies."
narrate "These include several libraries with known CVEs:"
echo ""
echo "  woodstox-core 6.0.3   — CVE-2022-40152 (XML DoS)       CVSS 7.5"
echo "  json-path 2.7.0       — CVE-2023-51074 (Stack overflow) CVSS 7.5"
echo "  org.json 20220320     — CVE-2023-5072 (JSON DoS)        CVSS 7.5"
echo "  spring-core 5.3.18    — CVE-2022-22968, CVE-2023-20861  CVSS 5.3+"
echo ""
narrate "Let's build it and see what the security tools find."
pause

narrate "Triggering the vulnerable build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-vulnerable.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
narrate "Watching pipeline logs..."
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

narrate "The build completed. The policies are in inform-only mode, so the app"
narrate "deployed despite its vulnerabilities. Let's examine what was found."
echo ""

if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}Trusted Profile Analyzer — SBOM Browser${NC}"
  echo -e "    ${GREEN}https://${TPA_URL_HOST}/sboms${NC}"
  narrate "  > Find the vulnerable catalog-app SBOM."
  narrate "  > Click in to see matched advisories and CVE counts."
  echo ""
fi
if [ -n "$ACS_URL" ]; then
  echo -e "  ${BOLD}Advanced Cluster Security — Violations${NC}"
  echo -e "    ${GREEN}https://${ACS_URL}/main/violations${NC}"
  narrate "  > Filter by namespace '${NAMESPACE}'."
  narrate "  > Note the policy violations — detected but not enforced."
  echo ""
fi
pause

# ─── ACT 2 ────────────────────────────────────────────────

banner "ACT 2: THE FIX — LIGHTWELL NETWORK"

narrate "Lightwell Network provides remediated versions of the same dependencies."
narrate "Same version, same API — a .rhlw suffix indicates backported security patches:"
echo ""
echo "  woodstox-core  6.0.3      ->  6.0.3.rhlw-00001"
echo "  json-path      2.7.0      ->  2.7.0.rhlw-00001"
echo "  org.json       20220320   ->  20220320.0.0.rhlw-00003"
echo "  spring-core    5.3.18     ->  5.3.18.rhlw-00003"
echo ""
narrate "No code changes required. Just switch the Maven profile."
pause

narrate "Triggering the remediated build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-remediated.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

narrate "Now let's compare the results side by side."
echo ""
if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}TPA — SBOM Browser${NC}"
  echo -e "    ${GREEN}https://${TPA_URL_HOST}/sboms${NC}"
  narrate "  > Find the remediated SBOM alongside the vulnerable one."
  narrate "  > Compare CVE counts — critical should be zero."
  echo ""
fi
if [ -n "$ACS_URL" ]; then
  echo -e "  ${BOLD}ACS — Violations${NC}"
  echo -e "    ${GREEN}https://${ACS_URL}/main/violations${NC}"
  narrate "  > Only the vulnerable deployment has violations."
  echo ""
  echo -e "  ${BOLD}ACS — Deployment Risk${NC}"
  echo -e "    ${GREEN}https://${ACS_URL}/main/risk${NC}"
  narrate "  > Compare risk scores between the two deployments."
  echo ""
fi
pause

# ─── ACT 3 ────────────────────────────────────────────────

banner "ACT 3: LOCK THE DOOR"

narrate "We've shown that Lightwell eliminates the CVEs. Now let's make sure"
narrate "vulnerable images can't be deployed going forward."
echo ""
narrate "Enabling build-time enforcement on ACS policies..."
echo ""

POLICY_NAMES=(
  "Lightwell Demo — Block Critical CVEs (CVSS >= 9.0)"
  "Lightwell Demo — Block Known CVEs"
)

for POLICY_NAME in "${POLICY_NAMES[@]}"; do
  echo -n "  Enabling enforcement: ${POLICY_NAME} ... "
  POLICY_ID=$(curl -sk "https://${ROX_CENTRAL_ENDPOINT}/v1/policies" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('policies', []):
    if p['name'] == '$POLICY_NAME':
        print(p['id'])
        break
" 2>/dev/null) || true

  if [ -z "$POLICY_ID" ]; then
    echo -e "${YELLOW}not found — skipping${NC}"
    continue
  fi

  POLICY_JSON=$(curl -sk "https://${ROX_CENTRAL_ENDPOINT}/v1/policies/${POLICY_ID}" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" 2>/dev/null)

  UPDATED=$(echo "$POLICY_JSON" | python3 -c "
import sys, json
p = json.load(sys.stdin)
p['enforcementActions'] = ['FAIL_BUILD_ENFORCEMENT']
p.pop('lastUpdated', None)
p.pop('SORTLifecycleStage', None)
p.pop('SORTEnforcement', None)
json.dump(p, sys.stdout)
" 2>/dev/null)

  RESULT=$(curl -sk -X PUT "https://${ROX_CENTRAL_ENDPOINT}/v1/policies/${POLICY_ID}" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$UPDATED" -w "%{http_code}" -o /dev/null 2>/dev/null) || true

  if [ "$RESULT" = "200" ]; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${YELLOW}HTTP $RESULT${NC}"
  fi
done

echo ""
narrate "Enforcement is now active. Any build that fails these policies"
narrate "will be blocked at the ACS image check step."
pause

narrate "Let's prove it. Re-triggering the vulnerable build (with enforcement, no soft-fail)..."
echo ""
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-vulnerable.yaml" \
  | sed 's/value: "true"/value: "false"/' \
  | oc create -n "$NAMESPACE" -f -
echo ""
narrate "Watch the pipeline — it should fail at acs-image-check."
echo ""
if [ -n "$OCP_URL" ]; then
  echo -e "  ${BOLD}OpenShift — Pipeline Runs${NC}"
  echo -e "    ${GREEN}${OCP_URL}/pipelines/ns/${NAMESPACE}${NC}"
  echo ""
fi
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

# ─── WRAP-UP ──────────────────────────────────────────────

banner "DEMO COMPLETE"

echo "  Key takeaways:"
echo ""
echo "    - Drop-in replacement — no code changes, no version upgrades"
echo "    - Critical CVEs eliminated at the dependency level"
echo "    - Container image signed with Sigstore/cosign"
echo "    - Full SBOM tracked in Trusted Profile Analyzer"
echo "    - ACS policies enforce compliance at build time"
echo "    - SLSA Level 3 build provenance for Lightwell artifacts"
echo ""
narrate "The Red Hat Advanced Developer Suite:"
echo "  Lightwell Network         — Remediated open-source dependencies"
echo "  Trusted Profile Analyzer  — SBOM & vulnerability management"
echo "  Advanced Cluster Security — Build-to-runtime policy enforcement"
echo ""
[ -n "$HUB_URL" ] && echo -e "Demo Hub: ${GREEN}https://${HUB_URL}${NC}" && echo ""
