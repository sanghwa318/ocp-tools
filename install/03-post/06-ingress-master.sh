# 06-ingress-master.sh
#!/bin/bash
set -euo pipefail

NAMESPACE='openshift-ingress-operator'
INGRESS_NAME='default'
INGRESS_REPLICAS="${INGRESS_REPLICAS:-3}"
TARGET_NODE_ROLE_KEY="${TARGET_NODE_ROLE_KEY:-node-role.kubernetes.io/master}"
TARGET_TOLERATION_KEY="${TARGET_TOLERATION_KEY:-node-role.kubernetes.io/master}"
TARGET_TOLERATION_EFFECT="${TARGET_TOLERATION_EFFECT:-NoSchedule}"

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
