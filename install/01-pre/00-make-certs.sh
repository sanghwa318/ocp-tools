#!/bin/bash
set -euo pipefail

# Default values (can be overridden by environment)
HOST="${HOST:-bastion}"
CLUSTER="${CLUSTER:-example}"
DOMAIN="${DOMAIN:-com}"

NAME="${CLUSTER}.${DOMAIN}"
CERT_DIR="${CERT_DIR:-./certs}"
CERT_KEY="${CERT_DIR}/domain.key"
CERT_CRT="${CERT_DIR}/domain.crt"
CA_TRUST_ANCHOR_DIR='/etc/pki/ca-trust/source/anchors'
CERT_DAYS="${CERT_DAYS:-36500}"

CERT_COUNTRY="${CERT_COUNTRY:-KR}"
CERT_STATE="${CERT_STATE:-Seoul}"
CERT_LOCALITY="${CERT_LOCALITY:-Seoul}"
CERT_ORG="${CERT_ORG:-LGU}"
CERT_ORG_UNIT="${CERT_ORG_UNIT:-NW}"
CERT_CN="${HOST}.${CLUSTER}.${DOMAIN}"

SAN_LIST=(
  "DNS:${HOST}.${CLUSTER}.${DOMAIN}"
)

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "run as root"
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    err "command not found: ${cmd}"
    exit 1
  }
}

build_san_string() {
  local san_string=""
  local item

  for item in "${SAN_LIST[@]}"; do
    if [[ -n "${san_string}" ]]; then
      san_string+=", "
    fi
    san_string+="${item}"
  done

  echo "${san_string}"
}

main() {
  require_root
  require_cmd openssl
  require_cmd update-ca-trust

  mkdir -p "${CERT_DIR}"

  if [[ -f "${CERT_CRT}" || -f "${CERT_KEY}" ]]; then
    err "certificate file already exists in ${CERT_DIR}"
    exit 1
  fi

  SAN_STRING="$(build_san_string)"

  log "generating certificate: ${CERT_CRT}"
  openssl req \
    -newkey rsa:4096 \
    -nodes \
    -sha256 \
    -keyout "${CERT_KEY}" \
    -x509 \
    -days "${CERT_DAYS}" \
    -out "${CERT_CRT}" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_LOCALITY}/O=${CERT_ORG}/OU=${CERT_ORG_UNIT}/CN=${CERT_CN}" \
    -addext "subjectAltName = ${SAN_STRING}"

  log "installing CA trust anchor"
  cp -f "${CERT_CRT}" "${CA_TRUST_ANCHOR_DIR}/"

  log "updating CA trust"
  update-ca-trust extract

  log "done"
  openssl x509 -in "${CERT_CRT}" -noout -subject -issuer -dates -ext subjectAltName
}

main "$@"
