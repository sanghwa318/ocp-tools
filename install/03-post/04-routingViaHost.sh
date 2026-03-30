#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/post.env"

NETWORK_CR_NAME="${NETWORK_CR_NAME:-cluster}"

main() {
  require_oc_login

  resource_exists "network.operator.openshift.io" "${NETWORK_CR_NAME}" || die "network CR not found: ${NETWORK_CR_NAME}"

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
