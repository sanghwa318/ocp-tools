#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"

HOSTS_DEST="${HOSTS_DEST:-/etc/hosts}"
BEGIN_MARKER="# BEGIN_GROWIN_HOSTS"
END_MARKER="# END_GROWIN_HOSTS"

build_managed_block() {
  {
    echo "${BEGIN_MARKER}"

    awk '
      BEGIN { FS="[[:space:]]+" }
      /^[[:space:]]*#/ { next }
      NF < 3 { next }
      {
        fqdn=$1
        ip=$3
        short=fqdn
        sub(/\..*$/, "", short)

        if (fqdn != "" && ip != "") {
          printf "%s %s %s\n", ip, fqdn, short
        }
      }
    ' "${INVENTORY_FILE}"

    echo "${END_MARKER}"
  } | awk '!seen[$0]++'
}

strip_old_managed_block() {
  local file="$1"

  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip       { print }
  ' "${file}"
}

main() {
  require_root
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  backup_file "${HOSTS_DEST}"

  local tmp_file
  tmp_file="$(mktemp)"

  {
    if [[ -f "${HOSTS_DEST}" ]]; then
      strip_old_managed_block "${HOSTS_DEST}"
    else
      cat <<'EOF'
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
    fi

    echo
    build_managed_block
  } | awk '
      BEGIN {
        localhost_v4_seen=0
        localhost_v6_seen=0
      }
      /^127\.0\.0\.1[[:space:]]+/ {
        if (!localhost_v4_seen) {
          print
          localhost_v4_seen=1
        }
        next
      }
      /^::1[[:space:]]+/ {
        if (!localhost_v6_seen) {
          print
          localhost_v6_seen=1
        }
        next
      }
      { print }
    ' > "${tmp_file}"

  mv -f "${tmp_file}" "${HOSTS_DEST}"

  log "updated ${HOSTS_DEST}"
  cat "${HOSTS_DEST}"
}

main "$@"
