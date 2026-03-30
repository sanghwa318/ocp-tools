#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

NAMED_CONF_TEMPLATE="${TEMPLATE_DIR}/named.conf.tmpl"
ZONE_FORWARD_TEMPLATE="${TEMPLATE_DIR}/zone.forward.tmpl"

NAMED_CONF_DEST="${NAMED_CONF_DEST:-/etc/named.conf}"
ZONE_DIR="${ZONE_DIR:-/var/named}"
ZONE_NAME="${ZONE_NAME:-${CLUSTER}.${DOMAIN}}"
ZONE_FORWARD_DEST="${ZONE_FORWARD_DEST:-${ZONE_DIR}/${ZONE_NAME}.zone}"
DNS_SERVICE="${DNS_SERVICE:-named}"

render_named_conf() {
  sed \
    -e "s|@@ZONE_NAME@@|${ZONE_NAME}|g" \
    -e "s|@@ZONE_FILE@@|${ZONE_FORWARD_DEST}|g" \
    "${NAMED_CONF_TEMPLATE}"
}

render_zone_forward() {
  local serial
  serial="$(date +%Y%m%d%H)"

  awk -v zone_name="${ZONE_NAME}" '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    {
      hostname=$1
      ip=$3
      print hostname " IN A " ip
    }
  ' "${INVENTORY_FILE}" > "${ZONE_FORWARD_DEST}.records"

  {
    sed \
      -e "s|@@ZONE_NAME@@|${ZONE_NAME}|g" \
      -e "s|@@SERIAL@@|${serial}|g" \
      "${ZONE_FORWARD_TEMPLATE}"
    echo
    cat "${ZONE_FORWARD_DEST}.records"
  } > "${ZONE_FORWARD_DEST}"

  rm -f "${ZONE_FORWARD_DEST}.records"
}

main() {
  require_root
  require_cmd named-checkconf
  require_cmd named-checkzone
  require_cmd systemctl

  [[ -f "${NAMED_CONF_TEMPLATE}" ]] || die "template not found: ${NAMED_CONF_TEMPLATE}"
  [[ -f "${ZONE_FORWARD_TEMPLATE}" ]] || die "template not found: ${ZONE_FORWARD_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  # This script fully manages /etc/named.conf for this install environment.
  ensure_dir "${ZONE_DIR}"

  backup_file "${NAMED_CONF_DEST}"
  backup_file "${ZONE_FORWARD_DEST}"

  render_named_conf > "${NAMED_CONF_DEST}"
  render_zone_forward

  named-checkconf "${NAMED_CONF_DEST}"
  named-checkzone "${ZONE_NAME}" "${ZONE_FORWARD_DEST}"

  systemctl enable --now "${DNS_SERVICE}"
  systemctl restart "${DNS_SERVICE}"

  log "updated DNS config"
}

main "$@"
