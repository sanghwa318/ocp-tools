#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"

HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
MANAGED_MARKER_BEGIN="# BEGIN_GROWIN_HOSTS"
MANAGED_MARKER_END="# END_GROWIN_HOSTS"

render_hosts_block() {
  echo "${MANAGED_MARKER_BEGIN}"
  echo "127.0.0.1 localhost"
  echo "::1 localhost localhost.localdomain localhost6 localhost6.localdomain6"
  echo

  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 6 { next }
    {
      hostname=$1
      role=$2
      ip=$3
      print ip " " hostname
    }
  ' "${INVENTORY_FILE}"

  echo "${MANAGED_MARKER_END}"
}

main() {
  require_root
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  backup_file "${HOSTS_FILE}"

  local tmp_file
  tmp_file="$(mktemp)"

  if [[ -f "${HOSTS_FILE}" ]]; then
    awk -v begin="${MANAGED_MARKER_BEGIN}" -v end="${MANAGED_MARKER_END}" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      skip != 1 { print }
    ' "${HOSTS_FILE}" > "${tmp_file}"
  fi

  {
    cat "${tmp_file}"
    [[ -s "${tmp_file}" ]] && echo
    render_hosts_block
  } > "${HOSTS_FILE}"

  rm -f "${tmp_file}"

  log "updated ${HOSTS_FILE}"
  tail -n 30 "${HOSTS_FILE}"
}

main "$@"
