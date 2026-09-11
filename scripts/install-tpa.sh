#!/bin/bash
set -euo pipefail

# Deploys TPA with all prerequisites on-cluster (PostgreSQL, MinIO, Keycloak).
# Requires: RHTPA operator installed from OperatorHub, oc logged in as cluster-admin.
# Usage: TPA_NAMESPACE=tpa-system ./install-tpa.sh

NAMESPACE="${TPA_NAMESPACE:-tpa-system}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPA_DIR="$SCRIPT_DIR/../manifests/tpa"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

echo -e "${BOLD}Installing Trusted Profile Analyzer${NC}"
echo -e "  Namespace:   ${NAMESPACE}"
echo -e "  Apps domain: ${APPS_DOMAIN}"
echo ""

# 1. Namespace
echo -e "${GREEN}1/8 Creating namespace${NC}"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"
echo ""

# 2. Prerequisites (PostgreSQL + MinIO + Keycloak)
echo -e "${GREEN}2/8 Deploying PostgreSQL, MinIO, and Keycloak${NC}"
oc delete configmap keycloak-realm-import -n "$NAMESPACE" 2>/dev/null || true
oc create configmap keycloak-realm-import \
  --from-file=trustify-realm.json="$TPA_DIR/keycloak-realm.json" \
  -n "$NAMESPACE"
sed "s/NAMESPACE/$NAMESPACE/g" "$TPA_DIR/prerequisites.yaml" \
  | grep -v "REALM_JSON_PLACEHOLDER" \
  | oc apply -n "$NAMESPACE" -f -
echo ""

# 3. Wait for prerequisites
echo -e "${GREEN}3/8 Waiting for prerequisites${NC}"
echo "   PostgreSQL..."
oc rollout status statefulset/postgresql -n "$NAMESPACE" --timeout=180s
echo "   MinIO..."
oc rollout status deployment/minio -n "$NAMESPACE" --timeout=120s
echo "   Keycloak..."
oc rollout status deployment/keycloak -n "$NAMESPACE" --timeout=180s
echo ""

# 4. Post-install: MinIO bucket + Keycloak realm + route
echo -e "${GREEN}4/8 Configuring MinIO bucket and Keycloak realm${NC}"
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
    # Ensure openid scope is assigned to both clients
    OPENID_ID=$(curl -sk "https://${KC_HOST}/admin/realms/trustify/client-scopes" \
      -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
for s in json.load(sys.stdin):
    if s['name']=='openid': print(s['id'])
" 2>/dev/null) || true
    if [ -n "$OPENID_ID" ]; then
      for CLIENT_ID_NAME in frontend walker; do
        CID=$(curl -sk "https://${KC_HOST}/admin/realms/trustify/clients" \
          -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c['clientId']=='$CLIENT_ID_NAME': print(c['id'])
" 2>/dev/null) || true
        if [ -n "$CID" ]; then
          curl -sk -X PUT "https://${KC_HOST}/admin/realms/trustify/clients/$CID/default-client-scopes/$OPENID_ID" \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null || true
        fi
      done
    fi
    break
  fi
  sleep 5
done
echo -e "   Keycloak issuer: ${KC_ISSUER}"
echo ""

# 5. Apply TPA CR
echo -e "${GREEN}5/8 Creating TPA instance${NC}"
sed \
  -e "s|KEYCLOAK_ISSUER_PLACEHOLDER|${KC_ISSUER}|g" \
  -e "s/NAMESPACE/$NAMESPACE/g" \
  -e "s/APPS_DOMAIN/$APPS_DOMAIN/g" \
  "$TPA_DIR/tpa-cr.yaml" | oc apply -n "$NAMESPACE" -f -
echo ""

# 6. Run database migration
echo -e "${GREEN}6/8 Waiting for server pod then running database migration${NC}"
oc rollout status deployment/server -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
sleep 10
SERVER_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SERVER_POD" ]; then
  oc exec -n "$NAMESPACE" "$SERVER_POD" -- /usr/local/bin/trustd db migrate 2>&1 | tail -5
  echo "   Migration complete. Setting UI scopes and restarting pods..."
  oc set env deployment/server -n "$NAMESPACE" \
    UI_SCOPE="openid create:document read:document update:document delete:document"
  oc rollout restart deployment/server -n "$NAMESPACE"
  oc rollout status deployment/server -n "$NAMESPACE" --timeout=120s
fi
echo ""

# 7. Upload advisory data
echo -e "${GREEN}7/8 Uploading advisory data${NC}"
ADV_TOKEN=$(curl -sk "https://${KC_HOST}/realms/trustify/protocol/openid-connect/token" \
  -d "client_id=walker" -d "client_secret=walker-secret-for-demo" \
  -d "grant_type=client_credentials" -d "scope=openid" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null) || true
if [ -n "$ADV_TOKEN" ]; then
  TPA_ROUTE=$(oc get route -n "$NAMESPACE" -l app.kubernetes.io/name=server -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
  for adv_file in "$TPA_DIR"/advisories/*.json; do
    [ -f "$adv_file" ] || continue
    fname=$(basename "$adv_file")
    ADV_RESP=$(curl -sk -X POST "https://${TPA_ROUTE}/api/v3/advisory" \
      -H "Authorization: Bearer $ADV_TOKEN" \
      -H "Content-Type: application/json" \
      -d @"$adv_file" -w "%{http_code}" -o /dev/null 2>/dev/null) || true
    if [ "$ADV_RESP" = "201" ] || [ "$ADV_RESP" = "200" ]; then
      echo -e "  ${fname}: ${GREEN}OK${NC}"
    elif [ "$ADV_RESP" = "409" ]; then
      echo -e "  ${fname}: ${YELLOW}already exists${NC}"
    else
      echo -e "  ${fname}: ${YELLOW}HTTP $ADV_RESP${NC}"
    fi
  done
  echo "  Seeding vulnerability metadata..."
  oc exec -i -n "$NAMESPACE" statefulset/postgresql -- \
    psql -U trustify -d trustify < "$TPA_DIR/seed-vulnerability-metadata.sql" 2>/dev/null \
    && echo -e "  ${GREEN}OK${NC}" \
    || echo -e "  ${YELLOW}seed SQL failed (non-critical)${NC}"
else
  echo -e "  ${YELLOW}Could not obtain token — upload advisories manually${NC}"
fi
echo ""

# 8. Summary
echo -e "${GREEN}8/8 Verifying${NC}"
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
