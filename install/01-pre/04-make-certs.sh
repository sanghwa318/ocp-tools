#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"

CERT_DIR="${CERT_DIR:-./certs}"
CERT_KEY="${CERT_DIR}/domain.key"
CERT_CRT="${CERT_DIR}/domain.crt"
CA_TRUST_ANCHOR_DIR="${CA_TRUST_ANCHOR_DIR:-/etc/pki/ca-trust/source/anchors}"
CERT_DAYS="${CERT_DAYS:-36500}"
CERT_IF_EXISTS="${CERT_IF_EXISTS:-fail}"
INSTALL_CA_TRUST="${INSTALL_CA_TRUST:-yes}"

CERT_COUNTRY="${CERT_COUNTRY:-KR}"
CERT_STATE="${CERT_STATE:-Seoul}"
CERT_LOCALITY="${CERT_LOCALITY:-Seoul}"
CERT_ORG="${CERT_ORG:-ORG}"
CERT_ORG_UNIT="${CERT_ORG_UNIT:-NW}"

NAME="${CLUSTER}.${DOMAIN}"
CERT_CN="${CERT_CN:-${HOST}.${NAME}}"
SAN_LIST_CSV="${SAN_LIST_CSV:-DNS:*.${NAME},DNS:${HOST}.${NAME}}"


build_san_string() {
  local san_string=""
  local item
  IFS=',' read -ra items <<< "${SAN_LIST_CSV}"

  for item in "${items[@]}"; do
    [[ -n "${san_string}" ]] && san_string+=", "
    san_string+="${item}"
  done

  echo "${san_string}"
}

handle_existing_cert() {
  if [[ -f "${CERT_CRT}" || -f "${CERT_KEY}" ]]; then
    case "${CERT_IF_EXISTS}" in
      fail)
        die "certificate file already exists in ${CERT_DIR}"
        ;;
      skip)
        log "certificate already exists, skipping"
        exit 0
        ;;
      replace)
        backup_file "${CERT_CRT}"
        backup_file "${CERT_KEY}"
        rm -f "${CERT_CRT}" "${CERT_KEY}"
        ;;
      *)
        die "invalid CERT_IF_EXISTS: ${CERT_IF_EXISTS}"
        ;;
    esac
  fi
}

main() {
  require_root
  require_cmd openssl
  require_cmd update-ca-trust

  ensure_dir "${CERT_DIR}"
  handle_existing_cert

  local san_string
  san_string="$(build_san_string)"

  openssl req \
    -newkey rsa:4096 \
    -nodes \
    -sha256 \
    -keyout "${CERT_KEY}" \
    -x509 \
    -days "${CERT_DAYS}" \
    -out "${CERT_CRT}" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_LOCALITY}/O=${CERT_ORG}/OU=${CERT_ORG_UNIT}/CN=${CERT_CN}" \
    -addext "subjectAltName = ${san_string}"

  if [[ "$(bool_normalize "${INSTALL_CA_TRUST}")" == "true" ]]; then
    cp -f "${CERT_CRT}" "${CA_TRUST_ANCHOR_DIR}/"
    update-ca-trust extract
  fi

  openssl x509 -in "${CERT_CRT}" -noout -subject -issuer -dates -ext subjectAltName
}

main "$@"
