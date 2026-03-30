#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

MANIFESTS_DIR="${MANIFESTS_DIR:-${INSTALL_WORKDIR}/manifests}"
OPENSHIFT_MANIFESTS_DIR="${OPENSHIFT_MANIFESTS_DIR:-${INSTALL_WORKDIR}/openshift}"

main() {
  require_root

  [[ -x "${OPENSHIFT_INSTALL_BIN}" ]] || die "openshift-install not found: ${OPENSHIFT_INSTALL_BIN}"
  [[ -d "${INSTALL_WORKDIR}" ]] || die "install workdir not found: ${INSTALL_WORKDIR}"
  [[ -f "${INSTALL_CONFIG_FILE}" ]] || die "install-config file not found: ${INSTALL_CONFIG_FILE}"

  [[ ! -d "${MANIFESTS_DIR}" ]] || die "manifests directory already exists: ${MANIFESTS_DIR}"
  [[ ! -d "${OPENSHIFT_MANIFESTS_DIR}" ]] || die "openshift manifests directory already exists: ${OPENSHIFT_MANIFESTS_DIR}"

  (
    cd "${INSTALL_WORKDIR}"
    "${OPENSHIFT_INSTALL_BIN}" create manifests
  )

  [[ -d "${MANIFESTS_DIR}" ]] || die "manifests directory not found: ${MANIFESTS_DIR}"
  [[ -d "${OPENSHIFT_MANIFESTS_DIR}" ]] || die "openshift manifests directory not found: ${OPENSHIFT_MANIFESTS_DIR}"

  log "generated manifests at ${MANIFESTS_DIR}"
  ls -ld "${MANIFESTS_DIR}" "${OPENSHIFT_MANIFESTS_DIR}"
}

main "$@"
