#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-env.sh"

NAMESPACE="$DEMO_NAMESPACE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Resetting Lightwell demo (${NAMESPACE} + ${CI_NAMESPACE})${NC}"
echo ""

echo -n "Deleting pipeline runs... "
tkn pipelinerun delete --all -f -n "$CI_NAMESPACE" 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

echo -n "Removing vulnerable deployment... "
oc delete -k "$PROJECT_DIR/manifests/overlays/vulnerable/" -n "$NAMESPACE" --ignore-not-found 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

echo -n "Removing remediated deployment... "
oc delete -k "$PROJECT_DIR/manifests/overlays/remediated/" -n "$NAMESPACE" --ignore-not-found 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

# --- Clean up ACS false positive exceptions created by vex-reconcile ---
if [ -f "$PROJECT_DIR/demo.env" ]; then
  source "$PROJECT_DIR/demo.env"
  ROX_CENTRAL_ENDPOINT="${ROX_CENTRAL_ENDPOINT:-$(oc get route -n rhacs-operator central -o jsonpath='{.spec.host}' 2>/dev/null):443}"
  if [ -n "${ROX_API_TOKEN:-}" ] && [ -n "${ROX_CENTRAL_ENDPOINT:-}" ]; then
    echo -n "Cleaning up ACS false positive exceptions... "
    EXCEPTION_IDS=$(curl -sk "https://$ROX_CENTRAL_ENDPOINT/v2/vulnerability-exceptions" \
      -H "Authorization: Bearer $ROX_API_TOKEN" 2>/dev/null \
      | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
for ex in d.get('exceptions', []):
    if not ex.get('expired', False):
        print(ex['id'])
" 2>/dev/null)
    CANCELLED=0
    for EID in $EXCEPTION_IDS; do
      curl -sk -X POST "https://$ROX_CENTRAL_ENDPOINT/v2/vulnerability-exceptions/$EID/cancel" \
        -H "Authorization: Bearer $ROX_API_TOKEN" >/dev/null 2>&1 && CANCELLED=$((CANCELLED + 1))
    done
    if [ "$CANCELLED" -gt 0 ]; then
      echo -e "${GREEN}cancelled $CANCELLED${NC}"
    else
      echo -e "${YELLOW}none found${NC}"
    fi
  fi
fi

echo ""
echo -e "${GREEN}Demo reset complete.${NC}"
echo ""
echo "The dashboard and pipeline definitions remain in place."
echo "Run 'make pipeline-vulnerable' or 'make pipeline-remediated' to start again."
echo ""
echo "To fully remove everything including the dashboard:"
echo "  oc delete project ${NAMESPACE} ${CI_NAMESPACE}"
