#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

DHCPD_TEMPLATE="${TEMPLATE_DIR}/dhcpd.conf.tmpl"
DHCPD_DEST="${DHCPD_DEST:-/etc/dhcp/dhcpd.conf}"
DHCP_SERVICE="${DHCP_SERVICE:-dhcpd}"

PXE_NEXT_SERVER="${PXE_NEXT_SERVER:-${PXE_BASTION_IP}}"
PXE_BIOS_BOOTFILE="${PXE_BIOS_BOOTFILE:-pxelinux.0}"
PXE_UEFI_BOOTFILE="${PXE_UEFI_BOOTFILE:-grubx64.efi}"

render_host_reservations() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    {
      hostname=$1
      ip=$3
      mac=$6
      print "host " hostname " {"
      print "  hardware ethernet " mac ";"
      print "  fixed-address " ip ";"
      print "}"
      print ""
    }
  ' "${INVENTORY_FILE}"
}

main() {
  require_root
  require_cmd dhcpd
  require_cmd systemctl

  [[ -f "${DHCPD_TEMPLATE}" ]] || die "template not found: ${DHCPD_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  backup_file "${DHCPD_DEST}"

  local reservations
  reservations="$(render_host_reservations)"

  sed \
    -e "s|@@SUBNET@@|${SUBNET%/*}|g" \
    -e "s|@@NETMASK@@|${PXE_NETMASK}|g" \
    -e "s|@@DHCP_RANGE_START@@|${DHCP_RANGE_START}|g" \
    -e "s|@@DHCP_RANGE_END@@|${DHCP_RANGE_END}|g" \
    -e "s|@@GATEWAY@@|${GATEWAY}|g" \
    -e "s|@@DNS_SERVER@@|${DNS_SERVER}|g" \
    -e "s|@@PXE_NEXT_SERVER@@|${PXE_NEXT_SERVER}|g" \
    -e "s|@@PXE_BIOS_BOOTFILE@@|${PXE_BIOS_BOOTFILE}|g" \
    -e "s|@@PXE_UEFI_BOOTFILE@@|${PXE_UEFI_BOOTFILE}|g" \
    -e "/@@HOST_RESERVATIONS@@/{
      s|@@HOST_RESERVATIONS@@|${reservations//$'\n'/\\n}|
    }" \
    "${DHCPD_TEMPLATE}" > "${DHCPD_DEST}"

  dhcpd -t -cf "${DHCPD_DEST}"
  systemctl enable --now "${DHCP_SERVICE}"
  systemctl restart "${DHCP_SERVICE}"

  log "updated ${DHCPD_DEST}"
}

main "$@"
