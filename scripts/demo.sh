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
  echo -e "\n${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}$1${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
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
echo "  Red Hat Advanced Developer Suite"
echo -e "${NC}"
echo ""
narrate "This demo shows how Lightwell Network, Trusted Profile Analyzer,"
narrate "and Advanced Cluster Security work together to secure your"
narrate "software supply chain — from dependency selection to production."
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
echo "  • woodstox-core 6.0.3   → CVE-2022-40152 (XML DoS)       CVSS 7.5"
echo "  • json-path 2.7.0       → CVE-2023-51074 (Stack overflow) CVSS 7.5"
echo "  • org.json 20220320     → CVE-2023-5072 (JSON DoS)        CVSS 7.5"
echo "  • spring-core 5.3.18    → CVE-2022-22968, CVE-2023-20861  CVSS 5.3+"
echo ""
narrate "Let's build it with these vulnerable dependencies and see what happens."
pause

narrate "Triggering the vulnerable build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-vulnerable.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
narrate "The Tekton pipeline will:"
echo "  1. Clone the source code"
echo "  2. Build with Maven (vulnerable profile)"
echo "  3. Build the container image"
echo "  4. Upload the SBOM to Trusted Profile Analyzer"
echo "  5. Check the image against ACS policies"
echo "  6. Scan the image for vulnerabilities"
echo "  7. Deploy (with soft-fail on policy violations)"
echo ""
narrate "Watching pipeline logs..."
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

banner "REVIEW: Vulnerable Build Results"
narrate "Now let's see what the security tools found. Open these views:"
echo ""
if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}Trusted Profile Analyzer:${NC}"
  echo -e "    SBOM Browser:    ${GREEN}https://${TPA_URL_HOST}/sbom${NC}"
  echo -e "    Advisories:      ${GREEN}https://${TPA_URL_HOST}/advisory${NC}"
  narrate "  → Find the vulnerable SBOM, click in to see the CVE list."
  narrate "  → Note the critical and high severity counts."
  echo ""
fi
if [ -n "$ACS_URL" ]; then
  echo -e "  ${BOLD}Advanced Cluster Security:${NC}"
  echo -e "    Violations:      ${GREEN}https://${ACS_URL}/main/violations${NC}"
  echo -e "    Risk:            ${GREEN}https://${ACS_URL}/main/risk${NC}"
  echo -e "    Image Vulns:     ${GREEN}https://${ACS_URL}/main/vulnerability-management/images${NC}"
  narrate "  → Filter violations by namespace '${NAMESPACE}'."
  narrate "  → Notice the policy violations fired by the vulnerable image."
  echo ""
fi
if [ -n "$OCP_URL" ]; then
  echo -e "  ${BOLD}OpenShift Console:${NC}"
  echo -e "    Pipelines:       ${GREEN}${OCP_URL}/pipelines/ns/${NAMESPACE}${NC}"
  echo -e "    Topology:        ${GREEN}${OCP_URL}/topology/ns/${NAMESPACE}${NC}"
  echo ""
fi
pause

# ─── ACT 2 ────────────────────────────────────────────────

banner "ACT 2: THE SOLUTION — LIGHTWELL NETWORK"

narrate "Lightwell Network provides remediated versions of the same dependencies."
narrate "The key difference? A .rhlw version suffix with backported security patches:"
echo ""
echo "  woodstox-core  6.0.3      →  6.0.3.rhlw-00001"
echo "  json-path      2.7.0      →  2.7.0.rhlw-00001"
echo "  org.json       20220320   →  20220320.0.0.rhlw-00003"
echo "  spring-core    5.3.18     →  5.3.18.rhlw-00003"
echo ""
narrate "Same version, same API compatibility. No code changes required."
narrate "Just switch the Maven profile from 'vulnerable' to 'remediated'."
pause

narrate "Triggering the remediated build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-remediated.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
narrate "This time the pipeline uses the 'remediated' Maven profile,"
narrate "pulling dependencies from Lightwell Network instead of Maven Central."
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

# ─── ACT 3 ────────────────────────────────────────────────

banner "ACT 3: VERIFIED AND TRUSTED"

narrate "Let's compare the results. Go back to the same views:"
echo ""
if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}TPA — SBOM Browser:${NC}  ${GREEN}https://${TPA_URL_HOST}/sbom${NC}"
  narrate "  → Find the remediated SBOM alongside the vulnerable one."
  narrate "  → Compare CVE counts — critical should be zero."
  echo ""
fi
if [ -n "$ACS_URL" ]; then
  echo -e "  ${BOLD}ACS — Violations:${NC}    ${GREEN}https://${ACS_URL}/main/violations${NC}"
  narrate "  → Filter by namespace. Only the vulnerable deployment has violations."
  narrate "  → The remediated deployment passes all policies."
  echo ""
  echo -e "  ${BOLD}ACS — Risk:${NC}          ${GREEN}https://${ACS_URL}/main/risk${NC}"
  narrate "  → Compare risk scores between the two deployments."
  echo ""
fi
if [ -n "$OCP_URL" ]; then
  echo -e "  ${BOLD}OpenShift — Topology:${NC} ${GREEN}${OCP_URL}/topology/ns/${NAMESPACE}${NC}"
  narrate "  → Both versions deployed side by side in the same namespace."
  echo ""
fi
pause

narrate "Key takeaways:"
echo ""
echo "  ✓  Drop-in replacement — no code changes, no version upgrades"
echo "  ✓  Critical CVEs eliminated at the dependency level"
echo "  ✓  Container image signed with Sigstore/cosign"
echo "  ✓  Full SBOM tracked in Trusted Profile Analyzer"
echo "  ✓  ACS policies pass — image cleared for production"
echo "  ✓  SLSA Level 3 build provenance for all Lightwell artifacts"
echo ""
pause

banner "DEMO COMPLETE"
narrate "The Red Hat Advanced Developer Suite provides:"
echo ""
echo "  • Lightwell Network         → Remediated open-source dependencies"
echo "  • Trusted Profile Analyzer  → SBOM & vulnerability management"
echo "  • Advanced Cluster Security → Build-to-runtime policy enforcement"
echo "  • Trusted Artifact Signer   → Cryptographic signing & provenance"
echo ""
narrate "Together, they deliver a complete secure software supply chain"
narrate "from code to production."
echo ""
[ -n "$HUB_URL" ] && echo -e "Demo Hub with all links: ${GREEN}https://${HUB_URL}${NC}" && echo ""
