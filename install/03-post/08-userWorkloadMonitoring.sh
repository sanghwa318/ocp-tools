# 08-user-workload-monitoring.sh
#!/bin/bash
set -euo pipefail

CLUSTER_MON_NS='openshift-monitoring'
CLUSTER_MON_CM='cluster-monitoring-config'
USER_WORKLOAD_NS='openshift-user-workload-monitoring'
USER_WORKLOAD_CM='user-workload-monitoring-config'
TARGET_NODE_ROLE_KEY="${TARGET_NODE_ROLE_KEY:-node-role.kubernetes.io/master}"
TARGET_TOLERATION_KEY="${TARGET_TOLERATION_KEY:-node-role.kubernetes.io/master}"
TARGET_TOLERATION_EFFECT="${TARGET_TOLERATION_EFFECT:-NoSchedule}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

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
  require_cmd oc
  check_oc
  apply_cluster_monitoring_config
  apply_user_workload_config
  verify
}

main "$@"
