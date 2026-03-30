#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/post.env"

NAMESPACE="${NAMESPACE:-openshift-ingress-operator}"
INGRESS_NAME="${INGRESS_NAME:-default}"

main() {
  require_oc_login

  log "patching ingresscontroller/${INGRESS_NAME}"
  oc patch ingresscontroller/"${INGRESS_NAME}" \
    -n "${NAMESPACE}" \
    --type=merge \
    -p "{
      \"spec\": {
        \"replicas\": ${INGRESS_REPLICAS},
        \"nodePlacement\": {
          \"nodeSelector\": {
            \"matchLabels\": {
              \"${TARGET_NODE_ROLE_KEY}\": \"\"
            }
          },
          \"tolerations\": [
            {
              \"key\": \"${TARGET_TOLERATION_KEY}\",
              \"operator\": \"Exists\",
              \"effect\": \"${TARGET_TOLERATION_EFFECT}\"
            }
          ]
        }
      }
    }"

  log "verifying ingresscontroller/${INGRESS_NAME}"
  oc get ingresscontroller/"${INGRESS_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}{"\n"}{.spec.nodePlacement.nodeSelector.matchLabels}{"\n"}{.spec.nodePlacement.tolerations}{"\n"}'
}

main "$@"
