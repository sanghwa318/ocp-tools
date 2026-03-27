# 07-whereabouts-reconciler.sh
#!/bin/bash
set -euo pipefail

MULTUS_NAMESPACE='openshift-multus'
CONFIGMAP_NAME='whereabouts-config'
RECONCILER_CRON_EXPRESSION="${RECONCILER_CRON_EXPRESSION:-*/5 * * * *}"

NETWORK_CR_NAME='cluster'
ADDITIONAL_NETWORK_NAME="${ADDITIONAL_NETWORK_NAME:-whereabouts-shim}"
ADDITIONAL_NETWORK_NAMESPACE="${ADDITIONAL_NETWORK_NAMESPACE:-default}"
ADDITIONAL_NETWORK_CNI_VERSION="${ADDITIONAL_NETWORK_CNI_VERSION:-0.3.1}"
ADDITIONAL_NETWORK_TYPE="${ADDITIONAL_NETWORK_TYPE:-bridge}"

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "command not found: $1"; exit 1; }
}

check_oc() {
  oc whoami >/dev/null 2>&1 || { err "oc is not logged in"; exit 1; }
}

ensure_configmap() {
  log "applying configmap ${CONFIGMAP_NAME}"
  oc create configmap "${CONFIGMAP_NAME}" \
    -n "${MULTUS_NAMESPACE}" \
    --from-literal=reconciler_cron_expression="${RECONCILER_CRON_EXPRESSION}" \
    --dry-run=client -o yaml | oc apply -f -
}

ensure_additional_network() {
  if oc get networks.operator.openshift.io/"${NETWORK_CR_NAME}" -o jsonpath='{range .spec.additionalNetworks[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -qx "${ADDITIONAL_NETWORK_NAME}"; then
    log "additionalNetwork ${ADDITIONAL_NETWORK_NAME} already exists, skipping"
    return 0
  fi

  if ! oc get networks.operator.openshift.io/"${NETWORK_CR_NAME}" -o jsonpath='{.spec.additionalNetworks}' 2>/dev/null | grep -q .; then
    log "initializing additionalNetworks list"
    oc patch networks.operator.openshift.io/"${NETWORK_CR_NAME}" \
      --type=json \
      -p '[{"op":"add","path":"/spec/additionalNetworks","value":[]}]' >/dev/null
  fi

  log "adding additionalNetwork ${ADDITIONAL_NETWORK_NAME}"
  oc patch networks.operator.openshift.io/"${NETWORK_CR_NAME}" \
    --type=json \
    -p "[
      {
        \"op\": \"add\",
        \"path\": \"/spec/additionalNetworks/-\",
        \"value\": {
          \"name\": \"${ADDITIONAL_NETWORK_NAME}\",
          \"namespace\": \"${ADDITIONAL_NETWORK_NAMESPACE}\",
          \"rawCNIConfig\": \"{\\n  \\\"name\\\": \\\"${ADDITIONAL_NETWORK_NAME}\\\",\\n  \\\"cniVersion\\\": \\\"${ADDITIONAL_NETWORK_CNI_VERSION}\\\",\\n  \\\"type\\\": \\\"${ADDITIONAL_NETWORK_TYPE}\\\",\\n  \\\"ipam\\\": {\\n    \\\"type\\\": \\\"whereabouts\\\"\\n  }\\n}\",
          \"type\": \"Raw\"
        }
      }
    ]"
}

verify() {
  log "verifying configmap ${CONFIGMAP_NAME}"
  oc get configmap "${CONFIGMAP_NAME}" -n "${MULTUS_NAMESPACE}" \
    -o jsonpath='{.data.reconciler_cron_expression}{"\n"}'

  log "verifying additionalNetwork ${ADDITIONAL_NETWORK_NAME}"
  oc get networks.operator.openshift.io/"${NETWORK_CR_NAME}" \
    -o jsonpath='{range .spec.additionalNetworks[*]}{.name}{" | "}{.namespace}{" | "}{.type}{"\n"}{end}' | grep "^${ADDITIONAL_NETWORK_NAME} |"
}

main() {
  require_cmd oc
  check_oc
  ensure_configmap
  ensure_additional_network
  verify
}

main "$@"
