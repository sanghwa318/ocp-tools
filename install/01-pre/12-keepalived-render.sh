#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

KEEPALIVED_TEMPLATE="${TEMPLATE_DIR}/keepalived.conf.tmpl"
KEEPALIVED_DEST="${KEEPALIVED_DEST:-/etc/keepalived/keepalived.conf}"
KEEPALIVED_SERVICE="${KEEPALIVED_SERVICE:-keepalived}"

LOCAL_HOSTNAME="${LOCAL_HOSTNAME:-$(hostname -s)}"
KEEPALIVED_INTERFACE="${KEEPALIVED_INTERFACE:-${NIC_NAME}}"
KEEPALIVED_VRID="${KEEPALIVED_VRID:-51}"
KEEPALIVED_AUTH_PASS="${KEEPALIVED_AUTH_PASS:-changeme123}"
KEEPALIVED_PRIORITY_MASTER="${KEEPALIVED_PRIORITY_MASTER:-150}"
KEEPALIVED_PRIORITY_BACKUP="${KEEPALIVED_PRIORITY_BACKUP:-100}"

get_bastion_count() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "bastion" { count++ }
    END { print count+0 }
  ' "${INVENTORY_FILE}"
}

get_local_ip() {
  awk -v local_host="${LOCAL_HOSTNAME}" '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $1 == local_host && $2 == "bastion" { print $3; exit }
  ' "${INVENTORY_FILE}"
}

get_unicast_peers() {
  awk -v local_host="${LOCAL_HOSTNAME}" '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "bastion" && $1 != local_host { print "    " $3 }
  ' "${INVENTORY_FILE}"
}

detect_state_and_priority() {
  local first_bastion
  first_bastion="$(awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "bastion" { print $1; exit }
  ' "${INVENTORY_FILE}")"

  if [[ "${LOCAL_HOSTNAME}" == "${first_bastion}" ]]; then
    KEEPALIVED_STATE="MASTER"
    KEEPALIVED_PRIORITY="${KEEPALIVED_PRIORITY_MASTER}"
  else
    KEEPALIVED_STATE="BACKUP"
    KEEPALIVED_PRIORITY="${KEEPALIVED_PRIORITY_BACKUP}"
  fi
}

main() {
  require_root
  require_cmd keepalived
  require_cmd systemctl

  [[ -f "${KEEPALIVED_TEMPLATE}" ]] || die "template not found: ${KEEPALIVED_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  local bastion_count
  bastion_count="$(get_bastion_count)"
  [[ "${bastion_count}" -ge 2 ]] || die "at least two bastion nodes are required"

  local local_ip
  local_ip="$(get_local_ip)"
  [[ -n "${local_ip}" ]] || die "local bastion IP not found for ${LOCAL_HOSTNAME}"

  detect_state_and_priority

  local unicast_peers
  unicast_peers="$(get_unicast_peers)"
  [[ -n "${unicast_peers}" ]] || die "failed to build unicast peers"

  backup_file "${KEEPALIVED_DEST}"

  sed \
    -e "s|@@INTERFACE@@|${KEEPALIVED_INTERFACE}|g" \
    -e "s|@@STATE@@|${KEEPALIVED_STATE}|g" \
    -e "s|@@PRIORITY@@|${KEEPALIVED_PRIORITY}|g" \
    -e "s|@@VRID@@|${KEEPALIVED_VRID}|g" \
    -e "s|@@AUTH_PASS@@|${KEEPALIVED_AUTH_PASS}|g" \
    -e "s|@@LOCAL_IP@@|${local_ip}|g" \
    -e "s|@@SERVICE_VIP@@|${SERVICE_VIP}|g" \
    -e "s|@@INGRESS_VIP@@|${INGRESS_VIP}|g" \
    -e "/@@UNICAST_PEERS@@/{
      s|@@UNICAST_PEERS@@|${unicast_peers//$'\n'/\\n}|
    }" \
    "${KEEPALIVED_TEMPLATE}" > "${KEEPALIVED_DEST}"

  keepalived -t -f "${KEEPALIVED_DEST}"
  systemctl enable --now "${KEEPALIVED_SERVICE}"
  systemctl restart "${KEEPALIVED_SERVICE}"

  log "updated ${KEEPALIVED_DEST}"
}

main "$@"
