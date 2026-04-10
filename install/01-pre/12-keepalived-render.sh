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

KEEPALIVED_TEMPLATE="${TEMPLATE_DIR}/keepalived.conf.tmpl"
KEEPALIVED_DEST="${KEEPALIVED_DEST:-/etc/keepalived/keepalived.conf}"
KEEPALIVED_SERVICE="${KEEPALIVED_SERVICE:-keepalived}"

VRRP_INSTANCE_NAME="${VRRP_INSTANCE_NAME:-OCP}"
if [[ -n "${VRRP_INTERFACE:-}" ]]; then
  :
elif [[ "${NETTYPE:-ethernet}" == "vlan" && -n "${VLAN_ID:-}" && "${VLAN_ID}" != "-" ]]; then
  VRRP_INTERFACE="${NIC_NAME}.${VLAN_ID}"
else
  VRRP_INTERFACE="${NIC_NAME}"
fi
VRRP_VIRTUAL_ROUTER_ID="${VRRP_VIRTUAL_ROUTER_ID:-100}"
VRRP_PRIORITY_PRIMARY="${VRRP_PRIORITY_PRIMARY:-200}"
VRRP_PRIORITY_SECONDARY="${VRRP_PRIORITY_SECONDARY:-100}"
VRRP_ADVERT_INT="${VRRP_ADVERT_INT:-5}"
VRRP_AUTH_TYPE="${VRRP_AUTH_TYPE:-PASS}"
VRRP_AUTH_PASS="${VRRP_AUTH_PASS:-changeme}"
VRRP_VIP="${VRRP_VIP:-${SERVICE_VIP}}"

get_bastion_nodes() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    $2 == "bastion" {
      print $1 "|" $3
    }
  ' "${INVENTORY_FILE}"
}

get_local_ip() {
  ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1
}

select_local_bastion() {
  local local_ips
  local bastion_line
  local name ip

  local_ips="$(get_local_ip || true)"

  while IFS= read -r bastion_line; do
    [[ -n "${bastion_line}" ]] || continue
    IFS='|' read -r name ip <<< "${bastion_line}"
    if printf '%s\n' "${local_ips}" | grep -qx "${ip}"; then
      echo "${name}|${ip}"
      return 0
    fi
  done < <(get_bastion_nodes)

  return 1
}

render_keepalived_conf() {
  local state="$1"
  local priority="$2"
  local unicast_src_ip="$3"
  local unicast_peers_block="$4"

  sed \
    -e "s|@@VRRP_INSTANCE_NAME@@|${VRRP_INSTANCE_NAME}|g" \
    -e "s|@@VRRP_INTERFACE@@|${VRRP_INTERFACE}|g" \
    -e "s|@@VRRP_STATE@@|${state}|g" \
    -e "s|@@VRRP_PRIORITY@@|${priority}|g" \
    -e "s|@@VRRP_VIRTUAL_ROUTER_ID@@|${VRRP_VIRTUAL_ROUTER_ID}|g" \
    -e "s|@@VRRP_ADVERT_INT@@|${VRRP_ADVERT_INT}|g" \
    -e "s|@@VRRP_AUTH_TYPE@@|${VRRP_AUTH_TYPE}|g" \
    -e "s|@@VRRP_AUTH_PASS@@|${VRRP_AUTH_PASS}|g" \
    -e "s|@@VRRP_VIP@@|${VRRP_VIP}|g" \
    -e "s|@@UNICAST_SRC_IP@@|${unicast_src_ip}|g" \
    -e "/@@UNICAST_PEERS@@/{
      s|@@UNICAST_PEERS@@|${unicast_peers_block//$'\n'/\\n}|
    }" \
    "${KEEPALIVED_TEMPLATE}"
}

get_interface_ipv4() {
	  local iface="$1"
	    ip -4 -o addr show dev "${iface}" scope global | awk '{print $4}' | cut -d/ -f1 | head -n1
    }

main() {
  require_root
  require_cmd awk
  require_cmd ip
  require_cmd systemctl
  require_cmd keepalived

  [[ -f "${KEEPALIVED_TEMPLATE}" ]] || die "template not found: ${KEEPALIVED_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  local bastion_lines bastion_count
  bastion_lines="$(get_bastion_nodes || true)"
  bastion_count="$(printf '%s\n' "${bastion_lines}" | sed '/^$/d' | wc -l | awk '{print $1}')"

  if [[ "${bastion_count}" -lt 2 ]]; then
    log "single bastion detected, skipping keepalived configuration"
    exit 0
  fi

#  local local_bastion local_name local_ip
#  local_bastion="$(select_local_bastion || true)"
#  [[ -n "${local_bastion}" ]] || die "this host is not listed as a bastion node in ${INVENTORY_FILE}"
#
#  IFS='|' read -r local_name local_ip <<< "${local_bastion}"
  local local_bastion local_name inventory_ip local_ip
  local_bastion="$(select_local_bastion || true)"
  [[ -n "${local_bastion}" ]] || die "this host is not listed as a bastion node in ${INVENTORY_FILE}"
   
  IFS='|' read -r local_name inventory_ip <<< "${local_bastion}"
   
  local_ip="$(get_interface_ipv4 "${VRRP_INTERFACE}" || true)"
  [[ -n "${local_ip}" ]] || die "no IPv4 address found on interface ${VRRP_INTERFACE}"


  local first_bastion first_name first_ip
  first_bastion="$(printf '%s\n' "${bastion_lines}" | sed '/^$/d' | head -n1)"
  IFS='|' read -r first_name first_ip <<< "${first_bastion}"

  local state priority
  if [[ "${local_name}" == "${first_name}" ]]; then
    state="MASTER"
    priority="${VRRP_PRIORITY_PRIMARY}"
  else
    state="BACKUP"
    priority="${VRRP_PRIORITY_SECONDARY}"
  fi

  local peer_block=""
  local line name ipaddr
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    IFS='|' read -r name ipaddr <<< "${line}"
    [[ "${ipaddr}" == "${local_ip}" ]] && continue
    peer_block="${peer_block}    ${ipaddr}"$'\n'
  done < <(printf '%s\n' "${bastion_lines}")

  [[ -n "${peer_block}" ]] || die "no peer bastion nodes found for keepalived"

  backup_file "${KEEPALIVED_DEST}"
  render_keepalived_conf "${state}" "${priority}" "${local_ip}" "${peer_block}" > "${KEEPALIVED_DEST}"

  keepalived -t -f "${KEEPALIVED_DEST}"
  systemctl enable --now "${KEEPALIVED_SERVICE}"
  systemctl restart "${KEEPALIVED_SERVICE}"

  log "updated ${KEEPALIVED_DEST}"
  sed -n '1,220p' "${KEEPALIVED_DEST}"
}

main "$@"
