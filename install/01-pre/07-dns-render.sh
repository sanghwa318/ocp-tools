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
ZONE_NAME="${ZONE_NAME:-${CLUSTER_NAME}.${BASE_DOMAIN}}"
ZONE_FORWARD_DEST="${ZONE_FORWARD_DEST:-${ZONE_DIR}/${ZONE_NAME}.zone}"
DNS_SERVICE="${DNS_SERVICE:-named}"

DNS_NS_NAME="${DNS_NS_NAME:-ns1}"
DNS_NS_IP="${DNS_NS_IP:-${PXE_BASTION_IP}}"

get_bastion_count() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    $2 == "bastion" { count++ }
    END { print count+0 }
  ' "${INVENTORY_FILE}"
}

get_effective_api_vip() {
  local bastion_count
  bastion_count="$(get_bastion_count)"

  if [[ "${bastion_count}" -lt 2 ]]; then
    echo "${PXE_BASTION_IP}"
  else
    echo "${SERVICE_VIP}"
  fi
}

get_effective_ingress_vip() {
  local bastion_count
  bastion_count="$(get_bastion_count)"

  if [[ "${bastion_count}" -lt 2 ]]; then
    echo "${PXE_BASTION_IP}"
  else
    echo "${INGRESS_VIP}"
  fi
}

render_named_conf() {
  sed \
    -e "s|@@ZONE_NAME@@|${ZONE_NAME}|g" \
    -e "s|@@ZONE_FILE@@|${ZONE_FORWARD_DEST}|g" \
    "${NAMED_CONF_TEMPLATE}"
}

render_zone_records() {
  local records_file="$1"
  local effective_api_vip
  local effective_ingress_vip

  effective_api_vip="$(get_effective_api_vip)"
  effective_ingress_vip="$(get_effective_ingress_vip)"

  {
    printf '%s IN A %s\n' "${DNS_NS_NAME}" "${DNS_NS_IP}"
    printf '@ IN A %s\n' "${PXE_BASTION_IP}"
    printf 'api IN A %s\n' "${effective_api_vip}"
    printf 'api-int IN A %s\n' "${effective_api_vip}"
    printf '*.apps IN A %s\n' "${effective_ingress_vip}"

    awk '
      BEGIN { FS="[[:space:]]+" }
      /^[[:space:]]*#/ { next }
      NF < 3 { next }
      {
        fqdn=$1
        ip=$3
        short=fqdn
        sub(/\..*$/, "", short)

        if (short != "" && ip != "") {
          printf "%s IN A %s\n", short, ip
        }
      }
    ' "${INVENTORY_FILE}"
  } | awk '!seen[$0]++' > "${records_file}"
}

render_zone_forward() {
  local serial records_file
  serial="$(date +%Y%m%d%H)"
  records_file="${ZONE_FORWARD_DEST}.records"

  render_zone_records "${records_file}"

  {
    sed \
      -e "s|@@ZONE_NAME@@|${ZONE_NAME}|g" \
      -e "s|@@SERIAL@@|${serial}|g" \
      "${ZONE_FORWARD_TEMPLATE}"
    echo
    cat "${records_file}"
  } > "${ZONE_FORWARD_DEST}"

  rm -f "${records_file}"
}

main() {
  require_root
  require_cmd named-checkconf
  require_cmd named-checkzone
  require_cmd systemctl

  [[ -f "${NAMED_CONF_TEMPLATE}" ]] || die "template not found: ${NAMED_CONF_TEMPLATE}"
  [[ -f "${ZONE_FORWARD_TEMPLATE}" ]] || die "template not found: ${ZONE_FORWARD_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

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
  sed -n '1,120p' "${ZONE_FORWARD_DEST}"
}

main "$@"
