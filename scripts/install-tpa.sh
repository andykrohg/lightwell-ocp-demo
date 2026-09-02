#!/bin/bash
set -euo pipefail

# Deploys TPA with all prerequisites on-cluster (PostgreSQL, MinIO, Keycloak).
# Requires: RHTPA operator installed from OperatorHub, oc logged in as cluster-admin.
# Usage: TPA_NAMESPACE=tpa-system ./install-tpa.sh

NAMESPACE="${TPA_NAMESPACE:-tpa-system}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPA_DIR="$SCRIPT_DIR/../manifests/tpa"

GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

echo -e "${BOLD}Installing Trusted Profile Analyzer${NC}"
echo -e "  Namespace:   ${NAMESPACE}"
echo -e "  Apps domain: ${APPS_DOMAIN}"
echo ""

# 1. Namespace
echo -e "${GREEN}1/7 Creating namespace${NC}"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"
echo ""

# 2. Prerequisites (PostgreSQL + MinIO + Keycloak)
echo -e "${GREEN}2/7 Deploying PostgreSQL, MinIO, and Keycloak${NC}"
oc delete configmap keycloak-realm-import -n "$NAMESPACE" 2>/dev/null || true
oc create configmap keycloak-realm-import \
  --from-file=trustify-realm.json="$TPA_DIR/keycloak-realm.json" \
  -n "$NAMESPACE"
sed "s/NAMESPACE/$NAMESPACE/g" "$TPA_DIR/prerequisites.yaml" \
  | grep -v "REALM_JSON_PLACEHOLDER" \
  | oc apply -n "$NAMESPACE" -f -
echo ""

# 3. Wait for prerequisites
echo -e "${GREEN}3/7 Waiting for prerequisites${NC}"
echo "   PostgreSQL..."
oc rollout status statefulset/postgresql -n "$NAMESPACE" --timeout=180s
echo "   MinIO..."
oc rollout status deployment/minio -n "$NAMESPACE" --timeout=120s
echo "   Keycloak..."
oc rollout status deployment/keycloak -n "$NAMESPACE" --timeout=180s
echo ""

# 4. Post-install: MinIO bucket + Keycloak realm + route
echo -e "${GREEN}4/7 Configuring MinIO bucket and Keycloak realm${NC}"
MINIO_POD=$(oc get pod -n "$NAMESPACE" -l app=minio -o jsonpath='{.items[0].metadata.name}')
oc exec -n "$NAMESPACE" "$MINIO_POD" -- \
  mc alias set local http://localhost:9000 minioadmin minioadmin-demo-password 2>/dev/null || true
oc exec -n "$NAMESPACE" "$MINIO_POD" -- \
  mc mb local/trustify 2>/dev/null || echo "   (bucket exists)"

oc create route edge keycloak --service=keycloak --port=8080 -n "$NAMESPACE" 2>/dev/null || true
KC_HOST=$(oc get route keycloak -n "$NAMESPACE" -o jsonpath='{.spec.host}')
KC_ISSUER="https://${KC_HOST}/realms/trustify"

# Import realm via API (ConfigMap import is unreliable)
echo "   Importing Keycloak realm..."
for i in $(seq 1 12); do
  TOKEN=$(curl -sk "https://${KC_HOST}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" -d "username=admin" -d "password=admin" \
    -d "grant_type=password" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null) || true
  if [ -n "$TOKEN" ]; then
    curl -sk -X POST "https://${KC_HOST}/admin/realms" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d @"$TPA_DIR/keycloak-realm.json" 2>/dev/null || true
    break
  fi
  sleep 5
done
echo -e "   Keycloak issuer: ${KC_ISSUER}"
echo ""

# 5. Apply TPA CR
echo -e "${GREEN}5/7 Creating TPA instance${NC}"
sed \
  -e "s|KEYCLOAK_ISSUER_PLACEHOLDER|${KC_ISSUER}|g" \
  -e "s/NAMESPACE/$NAMESPACE/g" \
  -e "s/APPS_DOMAIN/$APPS_DOMAIN/g" \
  "$TPA_DIR/tpa-cr.yaml" | oc apply -n "$NAMESPACE" -f -
echo ""

# 6. Run database migration
echo -e "${GREEN}6/7 Waiting for server pod then running database migration${NC}"
oc rollout status deployment/server -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
sleep 10
SERVER_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SERVER_POD" ]; then
  oc exec -n "$NAMESPACE" "$SERVER_POD" -- /usr/local/bin/trustd db migrate 2>&1 | tail -5
  echo "   Migration complete. Setting UI scopes and restarting pods..."
  oc set env deployment/server -n "$NAMESPACE" \
    UI_SCOPE="openid create:document read:document update:document delete:document"
  oc rollout restart deployment/server deployment/importer -n "$NAMESPACE"
  oc rollout status deployment/server -n "$NAMESPACE" --timeout=120s
  oc rollout status deployment/importer -n "$NAMESPACE" --timeout=120s
fi
echo ""

# 7. Summary
echo -e "${GREEN}7/7 Verifying${NC}"
TPA_ROUTE=$(oc get route -n "$NAMESPACE" -l app.kubernetes.io/name=server -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")

echo ""
echo -e "${BOLD}TPA installation complete!${NC}"
echo ""
echo -e "  TPA Console:     ${GREEN}https://${TPA_ROUTE}${NC}"
echo -e "  Keycloak Admin:  ${GREEN}https://${KC_HOST}/admin${NC}  (admin/admin)"
echo ""
echo "  For the demo scripts, export:"
echo "    export TPA_URL=https://${TPA_ROUTE}"
echo "    export TPA_CLIENT_ID=walker"
echo "    export TPA_CLIENT_SECRET=walker-secret-for-demo"
echo "    export TPA_OIDC_ISSUER=${KC_ISSUER}"
echo ""
