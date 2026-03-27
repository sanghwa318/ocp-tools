# 09-routing-via-host.sh
#!/bin/bash
set -euo pipefail

NETWORK_CR_NAME='cluster'
ROUTING_VIA_HOST="${ROUTING_VIA_HOST:-true}"
IP_FORWARDING_MODE="${IP_FORWARDING_MODE:-Global}"

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

main() {
  require_cmd oc
  check_oc

  log "patching network.operator.openshift.io/${NETWORK_CR_NAME}"
  oc patch network.operator.openshift.io/"${NETWORK_CR_NAME}" \
    --type=merge \
    -p "{
      \"spec\": {
        \"defaultNetwork\": {
          \"ovnKubernetesConfig\": {
            \"gatewayConfig\": {
              \"routingViaHost\": ${ROUTING_VIA_HOST},
              \"ipForwarding\": \"${IP_FORWARDING_MODE}\"
            }
          }
        }
      }
    }"

  log "verifying network.operator.openshift.io/${NETWORK_CR_NAME}"
  oc get network.operator.openshift.io/"${NETWORK_CR_NAME}" \
    -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.gatewayConfig.routingViaHost}{"\n"}{.spec.defaultNetwork.ovnKubernetesConfig.gatewayConfig.ipForwarding}{"\n"}'
}

main "$@"
