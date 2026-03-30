#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

HAPROXY_TEMPLATE="${TEMPLATE_DIR}/haproxy.cfg.tmpl"
HAPROXY_DEST="${HAPROXY_DEST:-/etc/haproxy/haproxy.cfg}"
HAPROXY_SERVICE="${HAPROXY_SERVICE:-haproxy}"

API_VIP="${API_VIP:-${SERVICE_VIP}}"

build_api_backend_lines() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "master" {
      printf "    server %s %s:6443 check\n", $1, $3
    }
  ' "${INVENTORY_FILE}"
}

build_mcs_backend_lines() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "master" {
      printf "    server %s %s:22623 check\n", $1, $3
    }
  ' "${INVENTORY_FILE}"
}

build_ingress_backend_lines() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 9 { next }
    $2 == "worker" || $2 == "infra" {
      printf "    server %s %s:%s check\n", $1, $3, PORT
    }
  ' PORT="$1" "${INVENTORY_FILE}"
}

main() {
  require_root
  require_cmd haproxy
  require_cmd systemctl

  [[ -f "${HAPROXY_TEMPLATE}" ]] || die "template not found: ${HAPROXY_TEMPLATE}"
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  backup_file "${HAPROXY_DEST}"

  local api_backend_lines
  local mcs_backend_lines
  local ingress_http_backend_lines
  local ingress_https_backend_lines

  api_backend_lines="$(build_api_backend_lines)"
  mcs_backend_lines="$(build_mcs_backend_lines)"
  ingress_http_backend_lines="$(build_ingress_backend_lines 80)"
  ingress_https_backend_lines="$(build_ingress_backend_lines 443)"

  [[ -n "${api_backend_lines}" ]] || die "no master nodes found for API backend"
  [[ -n "${mcs_backend_lines}" ]] || die "no master nodes found for MCS backend"
  [[ -n "${ingress_http_backend_lines}" ]] || die "no worker/infra nodes found for ingress HTTP backend"
  [[ -n "${ingress_https_backend_lines}" ]] || die "no worker/infra nodes found for ingress HTTPS backend"

  sed \
    -e "s|@@API_VIP@@|${API_VIP}|g" \
    -e "s|@@INGRESS_VIP@@|${INGRESS_VIP}|g" \
    -e "/@@API_BACKENDS@@/{
      s|@@API_BACKENDS@@|${api_backend_lines//$'\n'/\\n}|
    }" \
    -e "/@@MCS_BACKENDS@@/{
      s|@@MCS_BACKENDS@@|${mcs_backend_lines//$'\n'/\\n}|
    }" \
    -e "/@@INGRESS_HTTP_BACKENDS@@/{
      s|@@INGRESS_HTTP_BACKENDS@@|${ingress_http_backend_lines//$'\n'/\\n}|
    }" \
    -e "/@@INGRESS_HTTPS_BACKENDS@@/{
      s|@@INGRESS_HTTPS_BACKENDS@@|${ingress_https_backend_lines//$'\n'/\\n}|
    }" \
    "${HAPROXY_TEMPLATE}" > "${HAPROXY_DEST}"

  haproxy -c -f "${HAPROXY_DEST}"
  systemctl enable --now "${HAPROXY_SERVICE}"
  systemctl restart "${HAPROXY_SERVICE}"

  log "updated ${HAPROXY_DEST}"
}

main "$@"
