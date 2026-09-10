#!/bin/sh
set -e

export TPA_CONSOLE_URL="${TPA_CONSOLE_URL:-https://tpa.apps.example.com}"
export ACS_CONSOLE_URL="${ACS_CONSOLE_URL:-https://central-acs.apps.example.com}"
export OCP_CONSOLE_URL="${OCP_CONSOLE_URL:-https://console-openshift-console.apps.example.com}"
export DEMO_NAMESPACE="${DEMO_NAMESPACE:-lightwell-demo}"
export APPS_DOMAIN="${APPS_DOMAIN:-apps.example.com}"
export CI_NAMESPACE="${CI_NAMESPACE:-${DEMO_NAMESPACE}-ci}"

envsubst '${TPA_CONSOLE_URL} ${ACS_CONSOLE_URL} ${OCP_CONSOLE_URL} ${DEMO_NAMESPACE} ${APPS_DOMAIN} ${CI_NAMESPACE}' \
  < /opt/app-root/src/index.template.html \
  > /opt/app-root/src/index.html

exec nginx -g 'daemon off;'
