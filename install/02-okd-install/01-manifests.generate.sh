#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

MANIFESTS_DIR="${MANIFESTS_DIR:-${INSTALL_WORKDIR}/manifests}"

main() {
  require_root
  [[ -x "${OPENSHIFT_INSTALL_BIN}" ]] || die "openshift-install not found: ${OPENSHIFT_INSTALL_BIN}"
  [[ -f "${INSTALL_CONFIG_FILE}" ]] || die "install-config file not found: ${INSTALL_CONFIG_FILE}"

  backup_file "${INSTALL_CONFIG_FILE}"

  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" create manifests )

  [[ -d "${MANIFESTS_DIR}" ]] || die "manifests directory not created: ${MANIFESTS_DIR}"

  log "generated manifests at ${MANIFESTS_DIR}"
  ls -ld "${MANIFESTS_DIR}"
}

main "$@"
