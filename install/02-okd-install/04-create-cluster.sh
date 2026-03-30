#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

CREATE_CLUSTER_MODE="${CREATE_CLUSTER_MODE:-create-and-wait-bootstrap}"

run_create_cluster() {
  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" create cluster --log-level=info )
}

run_wait_bootstrap() {
  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" wait-for bootstrap-complete --log-level=info )
}

run_wait_install_complete() {
  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" wait-for install-complete --log-level=info )
}

main() {
  require_root
  [[ -x "${OPENSHIFT_INSTALL_BIN}" ]] || die "openshift-install not found: ${OPENSHIFT_INSTALL_BIN}"
  [[ -f "${INSTALL_CONFIG_FILE}" ]] || die "install-config file not found: ${INSTALL_CONFIG_FILE}"

  case "${CREATE_CLUSTER_MODE}" in
    create-only)
      run_create_cluster
      ;;
    wait-bootstrap-only)
      run_wait_bootstrap
      ;;
    wait-install-complete-only)
      run_wait_install_complete
      ;;
    create-and-wait-bootstrap)
      run_create_cluster
      run_wait_bootstrap
      ;;
    create-wait-bootstrap-wait-complete)
      run_create_cluster
      run_wait_bootstrap
      run_wait_install_complete
      ;;
    *)
      die "unsupported CREATE_CLUSTER_MODE: ${CREATE_CLUSTER_MODE}"
      ;;
  esac

  log "cluster install step completed: ${CREATE_CLUSTER_MODE}"
}

main "$@"
