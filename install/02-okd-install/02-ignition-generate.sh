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
  [[ -d "${MANIFESTS_DIR}" ]] || die "manifests directory not found: ${MANIFESTS_DIR}"

  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" create ignition-configs )

  [[ -f "${INSTALL_WORKDIR}/bootstrap.ign" ]] || die "bootstrap.ign not found"
  [[ -f "${INSTALL_WORKDIR}/master.ign" ]] || die "master.ign not found"
  [[ -f "${INSTALL_WORKDIR}/worker.ign" ]] || die "worker.ign not found"

  log "generated ignition configs"
  ls -l \
    "${INSTALL_WORKDIR}/bootstrap.ign" \
    "${INSTALL_WORKDIR}/master.ign" \
    "${INSTALL_WORKDIR}/worker.ign"
}

main "$@"
