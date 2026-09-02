#!/bin/bash
set -euo pipefail

NAMESPACE="${DEMO_NAMESPACE:-lightwell-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Resetting Lightwell demo in namespace: ${NAMESPACE}${NC}"
echo ""

echo -n "Deleting pipeline runs... "
tkn pipelinerun delete --all -f -n "$NAMESPACE" 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

echo -n "Removing vulnerable deployment... "
oc delete -k "$PROJECT_DIR/manifests/overlays/vulnerable/" -n "$NAMESPACE" --ignore-not-found 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

echo -n "Removing remediated deployment... "
oc delete -k "$PROJECT_DIR/manifests/overlays/remediated/" -n "$NAMESPACE" --ignore-not-found 2>/dev/null && echo -e "${GREEN}done${NC}" || echo -e "${YELLOW}skipped${NC}"

echo ""
echo -e "${GREEN}Demo reset complete.${NC}"
echo ""
echo "The dashboard and pipeline definitions remain in place."
echo "Run 'make demo' or './scripts/demo.sh' to start again."
echo ""
echo "To fully remove everything including the dashboard:"
echo "  oc delete project ${NAMESPACE}"
