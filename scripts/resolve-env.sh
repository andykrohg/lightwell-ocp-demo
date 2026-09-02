#!/bin/bash
# Resolves all demo environment variables by auto-detecting from the cluster.
# Sources demo.env for user-provided values (ROX_API_TOKEN).
# Meant to be sourced by other scripts: source "$(dirname "$0")/resolve-env.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/demo.env" ]; then
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/demo.env"
fi

export DEMO_NAMESPACE="${DEMO_NAMESPACE:-lightwell-demo}"
export TPA_NAMESPACE="${TPA_NAMESPACE:-tpa-system}"

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged into an OpenShift cluster. Run 'oc login' first." >&2
  exit 1
fi

export APPS_DOMAIN
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

export TPA_URL
TPA_URL="https://$(oc get route -n "$TPA_NAMESPACE" -l app.kubernetes.io/name=server -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "server.${APPS_DOMAIN}")"

KC_HOST=$(oc get route keycloak -n "$TPA_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "keycloak-${TPA_NAMESPACE}.${APPS_DOMAIN}")
export TPA_OIDC_ISSUER_URL="https://${KC_HOST}/realms/trustify/protocol/openid-connect/token"
export TPA_OIDC_ISSUER="https://${KC_HOST}/realms/trustify"

export TPA_CLIENT_ID="${TPA_CLIENT_ID:-walker}"
export TPA_CLIENT_SECRET="${TPA_CLIENT_SECRET:-walker-secret-for-demo}"

ROX_ROUTE=$(oc get route central -n rhacs-operator -o jsonpath='{.spec.host}' 2>/dev/null \
  || oc get route central -n stackrox -o jsonpath='{.spec.host}' 2>/dev/null \
  || echo "")
if [ -z "$ROX_ROUTE" ]; then
  ROX_ROUTE=$(oc get route -A -l app.kubernetes.io/name=central -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
fi
export ROX_CENTRAL_ENDPOINT="${ROX_CENTRAL_ENDPOINT:-${ROX_ROUTE}:443}"

export TPA_CONSOLE_URL="$TPA_URL"
export ACS_CONSOLE_URL="https://${ROX_ROUTE}"
export OCP_CONSOLE_URL="https://console-openshift-console.${APPS_DOMAIN}"

export ROX_API_TOKEN="${ROX_API_TOKEN:-}"
