#!/bin/sh
set -e

export TPA_CONSOLE_URL="${TPA_CONSOLE_URL:-https://tpa.apps.example.com}"
export ACS_CONSOLE_URL="${ACS_CONSOLE_URL:-https://central-acs.apps.example.com}"
export OCP_CONSOLE_URL="${OCP_CONSOLE_URL:-https://console-openshift-console.apps.example.com}"
export DEMO_NAMESPACE="${DEMO_NAMESPACE:-lightwell-demo}"

envsubst '${TPA_CONSOLE_URL} ${ACS_CONSOLE_URL} ${OCP_CONSOLE_URL} ${DEMO_NAMESPACE}' \
  < /usr/share/nginx/html/index.template.html \
  > /usr/share/nginx/html/index.html

exec nginx -g 'daemon off;'
