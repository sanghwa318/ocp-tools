#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

AUTH_DIR="${AUTH_DIR:-${INSTALL_WORKDIR}/auth}"

main() {
  require_root

  [[ -x "${OPENSHIFT_INSTALL_BIN}" ]] || die "openshift-install not found: ${OPENSHIFT_INSTALL_BIN}"
  [[ -d "${INSTALL_WORKDIR}" ]] || die "install workdir not found: ${INSTALL_WORKDIR}"
  [[ -d "${AUTH_DIR}" ]] || die "auth directory not found: ${AUTH_DIR}"
  [[ -f "${INSTALL_WORKDIR}/bootstrap.ign" ]] || die "bootstrap.ign not found"
  [[ -f "${INSTALL_WORKDIR}/master.ign" ]] || die "master.ign not found"
  [[ -f "${INSTALL_WORKDIR}/worker.ign" ]] || die "worker.ign not found"

  ( cd "${INSTALL_WORKDIR}" && "${OPENSHIFT_INSTALL_BIN}" create cluster )

  log "cluster creation command completed"
}

main "$@"
