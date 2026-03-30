#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"

SELINUX_CONFIG="${SELINUX_CONFIG:-/etc/selinux/config}"
TARGET_SELINUX_STATE="${TARGET_SELINUX_STATE:-disabled}"

main() {
  require_root

  [[ -f "${SELINUX_CONFIG}" ]] || die "SELinux config not found: ${SELINUX_CONFIG}"
  [[ "${TARGET_SELINUX_STATE}" =~ ^(disabled|permissive|enforcing)$ ]] || die "invalid TARGET_SELINUX_STATE: ${TARGET_SELINUX_STATE}"

  if grep -q "^SELINUX=${TARGET_SELINUX_STATE}$" "${SELINUX_CONFIG}"; then
    log "SELinux already set to ${TARGET_SELINUX_STATE}"
    exit 0
  fi

  backup_file "${SELINUX_CONFIG}"

  if grep -q '^SELINUX=' "${SELINUX_CONFIG}"; then
    sed -i "s/^SELINUX=.*/SELINUX=${TARGET_SELINUX_STATE}/" "${SELINUX_CONFIG}"
  else
    echo "SELINUX=${TARGET_SELINUX_STATE}" >> "${SELINUX_CONFIG}"
  fi

  log "SELinux updated to ${TARGET_SELINUX_STATE}"
  log "reboot required for full effect"
}

main "$@"
