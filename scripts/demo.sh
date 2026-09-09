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
echo "  1. The Problem  — Build a vulnerable app, see the CVE, exploit it live"
echo "  2. The Fix      — Rebuild with Lightwell Network, see the CVE suppressed"
echo "  3. Lock the Door — Enable enforcement so vulnerable builds fail"
echo ""
[ -n "$HUB_URL" ] && echo -e "  Demo Hub:  ${GREEN}https://${HUB_URL}${NC}"
[ -n "$TPA_URL_HOST" ] && echo -e "  TPA:       ${GREEN}https://${TPA_URL_HOST}${NC}"
[ -n "$ACS_URL" ] && echo -e "  ACS:       ${GREEN}https://${ACS_URL}${NC}"
[ -n "$OCP_URL" ] && echo -e "  OpenShift: ${GREEN}${OCP_URL}${NC}"
pause

# ─── ACT 1 ────────────────────────────────────────────────

banner "ACT 1: THE PROBLEM"

narrate "We have a catalog microservice that uses woodstox-core 6.0.3 for XML parsing."
narrate "This version contains CVE-2022-40152 — a denial-of-service vulnerability"
narrate "where a tiny crafted XML document (~1 KB) triggers unbounded recursion"
narrate "in the DTD parser, crashing the service with a StackOverflowError."
echo ""
echo "  woodstox-core 6.0.3  —  CVE-2022-40152 (XML DoS)  —  Medium severity"
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
echo -e "  ${BOLD}Pipeline vex-check Results${NC}"
narrate "  The vex-check step scanned the SBOM for known vulnerabilities."
narrate "  Since the vulnerable build uses unpatched Maven Central dependencies,"
narrate "  VEX data doesn't apply — CVE-2022-40152 remains in the findings."
echo ""

if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}Trusted Profile Analyzer — SBOM Browser${NC}"
  echo -e "    ${GREEN}https://${TPA_URL_HOST}/sboms${NC}"
  narrate "  > Find the vulnerable catalog-app SBOM."
  narrate "  > Click in to see matched advisories."
  echo ""
fi
if [ -n "$ACS_URL" ]; then
  echo -e "  ${BOLD}Advanced Cluster Security — Violations${NC}"
  echo -e "    ${GREEN}https://${ACS_URL}/main/violations${NC}"
  narrate "  > Filter by namespace '${NAMESPACE}'."
  narrate "  > Note the CVE-2022-40152 policy violation flagged by ACS."
  echo ""
fi
pause

narrate "Now let's prove this CVE is exploitable."
echo ""
echo -e "  ${BOLD}Live Exploit — CVE-2022-40152${NC}"
narrate "  We'll send a tiny XML payload with deeply nested DTD element"
narrate "  declarations. The unpatched parser recurses without limit"
narrate "  and crashes with a StackOverflowError."
echo ""
echo "  Run:  ./scripts/exploit-demo.sh http://<vulnerable-app-route>"
pause

# ─── ACT 2 ────────────────────────────────────────────────

banner "ACT 2: THE FIX — LIGHTWELL NETWORK"

narrate "Lightwell Network provides a remediated version of woodstox-core."
narrate "Same version, same API — a .rhlw suffix indicates a backported security patch:"
echo ""
echo "  woodstox-core  6.0.3  →  6.0.3.rhlw-00001"
echo ""
narrate "The patch adds a recursion depth limit of 500 to the DTD parser."
narrate "No code changes required — just activate the remediated Maven profile."
echo ""
narrate "Lightwell also publishes VEX data alongside remediated packages."
narrate "The pipeline uses this to verify which CVEs are resolved."
pause

narrate "Triggering the remediated build pipeline..."
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-remediated.yaml" | oc create -n "$NAMESPACE" -f -
echo ""
tkn pipelinerun logs -f --last -n "$NAMESPACE" 2>/dev/null || \
  narrate "(Pipeline logs not available — check OpenShift console)"
pause

narrate "Now let's compare the vex-check results."
echo ""
echo -e "  ${BOLD}Pipeline vex-check — Before vs. After${NC}"
narrate "  The same scan ran, but this time VEX data was applied."
narrate "  CVE-2022-40152 is now suppressed — it's confirmed as patched"
narrate "  in the .rhlw build."
echo ""
narrate "  Check the pipeline run logs to see the summary:"
narrate "    Total vulnerabilities → Suppressed by VEX → Remaining"
echo ""

if [ -n "$TPA_URL_HOST" ]; then
  echo -e "  ${BOLD}TPA — SBOM Browser${NC}"
  echo -e "    ${GREEN}https://${TPA_URL_HOST}/sboms${NC}"
  narrate "  > Find the remediated SBOM alongside the vulnerable one."
  narrate "  > Note the .rhlw version number for woodstox-core."
  echo ""
fi
pause

narrate "Let's also prove the remediation works."
narrate "The same exploit payload that crashed the vulnerable app"
narrate "is rejected cleanly by the Lightwell-patched version."
echo ""
echo -e "  ${BOLD}Exploit Demo — Remediated${NC}"
echo "  ./scripts/exploit-demo.sh http://<vulnerable-route> http://<remediated-route>"
echo ""
narrate "  The vulnerable app crashes (HTTP 500). The remediated app handles it safely."
pause

# ─── ACT 3 ────────────────────────────────────────────────

banner "ACT 3: LOCK THE DOOR"

narrate "We've shown that Lightwell eliminates CVE-2022-40152 and that VEX data"
narrate "lets the pipeline distinguish real vulnerabilities from resolved ones."
narrate ""
narrate "Now let's enforce it: require VEX remediation data before builds proceed."
echo ""
narrate "We'll re-run the vulnerable build with REQUIRE_VEX enabled."
narrate "Since the vulnerable woodstox doesn't match any VEX statements,"
narrate "zero CVEs are suppressed — and the pipeline fails."
pause

narrate "Triggering the vulnerable build with VEX enforcement (REQUIRE_VEX=true)..."
echo ""
sed_pipelinerun "$PROJECT_DIR/tekton/pipelinerun-vulnerable.yaml" \
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

narrate "The vulnerable build was blocked. Without Lightwell's remediated"
narrate "dependency, CVE-2022-40152 remains — and VEX enforcement catches it."
echo ""
narrate "Combined with cosign image signing (which runs on every build),"
narrate "the supply chain is locked down:"
echo "  1. Only builds with verified remediation proceed (pipeline vex-check)"
echo "  2. Only pipeline-built images are trusted (cosign signature)"
echo "  3. ACS monitors CVE-2022-40152 and enforces signature verification at deploy time"
echo "  4. TPA tracks every SBOM for full visibility"
pause

# ─── WRAP-UP ──────────────────────────────────────────────

banner "DEMO COMPLETE"

echo "  Key takeaways:"
echo ""
echo "    - Drop-in replacement — no code changes, just switch the Maven profile"
echo "    - CVE-2022-40152 eliminated at the dependency level"
echo "    - VEX data enables accurate vulnerability assessment"
echo "    - Pipeline enforcement blocks builds with unresolved CVEs"
echo "    - Container image signed with Sigstore/cosign"
echo "    - Full SBOM tracked in Trusted Profile Analyzer"
echo ""
narrate "The Red Hat Advanced Developer Suite:"
echo "  Lightwell Network         — Remediated open-source dependencies"
echo "  Trusted Profile Analyzer  — SBOM & vulnerability management"
echo "  Advanced Cluster Security — Build-to-runtime policy enforcement"
echo ""
[ -n "$HUB_URL" ] && echo -e "Demo Hub: ${GREEN}https://${HUB_URL}${NC}" && echo ""
