#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/post.env"

CLUSTER_MON_NS="${CLUSTER_MON_NS:-openshift-monitoring}"
CLUSTER_MON_CM="${CLUSTER_MON_CM:-cluster-monitoring-config}"
USER_WORKLOAD_NS="${USER_WORKLOAD_NS:-openshift-user-workload-monitoring}"
USER_WORKLOAD_CM="${USER_WORKLOAD_CM:-user-workload-monitoring-config}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

apply_cluster_monitoring_config() {
  log "enabling user workload monitoring"
  cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CLUSTER_MON_CM}
  namespace: ${CLUSTER_MON_NS}
data:
  config.yaml: |
    enableUserWorkload: true
EOF
}

apply_user_workload_config() {
  local config_file="${TMP_DIR}/config.yaml"

  cat > "${config_file}" <<EOF
prometheusOperator:
  nodeSelector:
    ${TARGET_NODE_ROLE_KEY}: ""
  tolerations:
  - key: ${TARGET_TOLERATION_KEY}
    operator: Exists
    effect: ${TARGET_TOLERATION_EFFECT}
prometheus:
  nodeSelector:
    ${TARGET_NODE_ROLE_KEY}: ""
  tolerations:
  - key: ${TARGET_TOLERATION_KEY}
    operator: Exists
    effect: ${TARGET_TOLERATION_EFFECT}
thanosRuler:
  nodeSelector:
    ${TARGET_NODE_ROLE_KEY}: ""
  tolerations:
  - key: ${TARGET_TOLERATION_KEY}
    operator: Exists
    effect: ${TARGET_TOLERATION_EFFECT}
EOF

  log "applying ${USER_WORKLOAD_CM}"
  oc create configmap "${USER_WORKLOAD_CM}" \
    -n "${USER_WORKLOAD_NS}" \
    --from-file=config.yaml="${config_file}" \
    --dry-run=client -o yaml | oc apply -f -
}

verify() {
  log "verifying ${CLUSTER_MON_CM}"
  oc get configmap "${CLUSTER_MON_CM}" -n "${CLUSTER_MON_NS}" \
    -o jsonpath='{.data.config\.yaml}{"\n"}'

  log "verifying ${USER_WORKLOAD_CM}"
  oc get configmap "${USER_WORKLOAD_CM}" -n "${USER_WORKLOAD_NS}" \
    -o jsonpath='{.data.config\.yaml}{"\n"}'
}

main() {
  require_oc_login
  apply_cluster_monitoring_config
  apply_user_workload_config
  verify
}

main "$@"
