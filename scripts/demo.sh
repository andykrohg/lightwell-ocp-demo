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
echo "  1. The Problem  — Build a vulnerable app, see the CVEs the pipeline finds"
echo "  2. The Fix      — Rebuild with Lightwell Network + VEX, see CVEs suppressed"
echo "  3. Lock the Door — Enable enforcement so vulnerable builds fail"
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
echo "  woodstox-core 6.0.3   — CVE-2022-40152 (XML DoS)            Medium"
echo "  json-path 2.7.0       — CVE-2023-51074 (Stack overflow)    Medium"
echo "  org.json 20220320     — CVE-2023-5072, CVE-2022-45688      High"
echo "  spring-core 5.3.18    — CVE-2025-41249, CVE-2026-41848     High"
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

narrate "The build completed. Let's look at what the pipeline found."
echo ""
echo -e "  ${BOLD}Pipeline VEX Check Results${NC}"
narrate "  The vex-check step scanned the SBOM for known vulnerabilities."
narrate "  Since the vulnerable build uses unpatched Maven Central dependencies,"
narrate "  VEX data doesn't apply — all CVEs remain in the findings."
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
  narrate "  > Note the policy violations flagged by ACS (inform mode)."
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
narrate ""
narrate "Lightwell also publishes VEX (Vulnerability Exploitability eXchange) data"
narrate "for its remediated packages. VEX tells downstream tooling: 'this CVE has"
narrate "been resolved in this build — the vulnerable code is not present.'"
pause

narrate "Triggering the remediated build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-remediated.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

narrate "Now let's compare the vex-check results."
echo ""
echo -e "  ${BOLD}Pipeline VEX Check — Before vs. After${NC}"
narrate "  The same vex-check step ran, but this time Lightwell's VEX data"
narrate "  was applied. The 6 CVEs covered by VEX are now suppressed —"
narrate "  they're confirmed as patched in the .rhlw builds."
echo ""
narrate "  Check the pipeline run logs to see the summary:"
narrate "    Total vulnerabilities → Suppressed by VEX → Remaining"
echo ""

if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}TPA — SBOM Browser${NC}"
  echo -e "    ${GREEN}https://${TPA_URL_HOST}/sboms${NC}"
  narrate "  > Find the remediated SBOM alongside the vulnerable one."
  narrate "  > The SBOM tracks which versions were used and their provenance."
  echo ""
fi
pause

narrate "Let's also prove the remediation works functionally."
narrate "CVE-2022-40152 is an XML DTD recursion DoS. A tiny payload (<1 KB) crashes"
narrate "the vulnerable app. The Lightwell-patched version rejects it safely."
echo ""
echo -e "  ${BOLD}Exploit Demo${NC}"
echo "  ./scripts/exploit-demo.sh"
echo ""
narrate "  Run this from the terminal to see the vulnerable app crash (HTTP 500)"
narrate "  while the remediated app handles the payload cleanly."
pause

# ─── ACT 3 ────────────────────────────────────────────────

banner "ACT 3: LOCK THE DOOR"

narrate "We've shown that Lightwell eliminates the CVEs and that VEX data"
narrate "lets the pipeline distinguish real vulnerabilities from resolved ones."
narrate ""
narrate "Now let's enforce it: require that builds include verified"
narrate "VEX remediation data before they can proceed."
echo ""
narrate "We'll re-run the vulnerable build with REQUIRE_VEX enabled."
narrate "Since the vulnerable dependencies don't match any VEX statements,"
narrate "zero CVEs are suppressed — and the pipeline will fail."
pause

narrate "Triggering the vulnerable build with VEX enforcement (REQUIRE_VEX=true)..."
echo ""
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-vulnerable.yaml" \
  | sed 's/value: "true"/value: "false"/' \
  | awk '/name: SOFT_FAIL/{print; getline; print; print "    - name: REQUIRE_VEX"; print "      value: \"true\""; next}1' \
  | oc create -n "$NAMESPACE" -f -
echo ""
narrate "Watch the pipeline — it should fail at the vex-check step."
echo ""
if [ -n "$OCP_URL" ]; then
  echo -e "  ${BOLD}OpenShift — Pipeline Runs${NC}"
  echo -e "    ${GREEN}${OCP_URL}/pipelines/ns/${NAMESPACE}${NC}"
  echo ""
fi
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

narrate "The vulnerable build was blocked. VEX data didn't match any of"
narrate "the standard Maven Central versions, so zero CVEs were suppressed."
echo ""
narrate "Meanwhile, the remediated build passes this same check —"
narrate "Lightwell's VEX data suppresses 6 known CVEs, proving the"
narrate "dependencies include verified remediation."
echo ""
narrate "Combined with cosign image signing (which runs on every build),"
narrate "the pipeline now ensures:"
echo "  1. Only builds with resolved vulnerabilities proceed (VEX check)"
echo "  2. Only pipeline-built images are trusted (cosign signature)"
echo "  3. ACS enforces signature verification at deploy time"
pause

# ─── WRAP-UP ──────────────────────────────────────────────

banner "DEMO COMPLETE"

echo "  Key takeaways:"
echo ""
echo "    - Drop-in replacement — no code changes, no version upgrades"
echo "    - Critical CVEs eliminated at the dependency level"
echo "    - VEX data enables accurate vulnerability assessment"
echo "    - Pipeline enforcement blocks builds with unresolved CVEs"
echo "    - Container image signed with Sigstore/cosign"
echo "    - Full SBOM tracked in Trusted Profile Analyzer"
echo "    - SLSA Level 3 build provenance for Lightwell artifacts"
echo ""
narrate "The Red Hat Advanced Developer Suite:"
echo "  Lightwell Network         — Remediated open-source dependencies"
echo "  Trusted Profile Analyzer  — SBOM & vulnerability management"
echo "  Advanced Cluster Security — Build-to-runtime policy enforcement"
echo ""
[ -n "$HUB_URL" ] && echo -e "Demo Hub: ${GREEN}https://${HUB_URL}${NC}" && echo ""
