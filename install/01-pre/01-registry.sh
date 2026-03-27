#!/bin/bash
set -euo pipefail

HOST='bastion'
CLUSTER='lgu'
DOMAIN='okd'
export HOST CLUSTER DOMAIN

REGISTRIES=(
  "infra_registry:/NFS/infra_registry:5000"
  "cnf_registry:/NFS/cnf_registry:5001"
)

REGISTRY_CONTAINER_PORT='5000'
BASE_REGISTRY_IMAGE='docker.io/registry'
CERT_DIR='./certs'
CERT_FILE='domain.crt'
KEY_FILE='domain.key'

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

##################################################################

if ! command -v podman >/dev/null 2>&1; then
  err "podman not found"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  err "systemctl not found"
  exit 1
fi

if [[ ! -f "${CERT_DIR}/${CERT_FILE}" ]]; then
  err "certificate file not found: ${CERT_DIR}/${CERT_FILE}"
  exit 1
fi

if [[ ! -f "${CERT_DIR}/${KEY_FILE}" ]]; then
  err "key file not found: ${CERT_DIR}/${KEY_FILE}"
  exit 1
fi

TAR_FILE="$(find . -maxdepth 1 -type f | sed 's#^\./##' | grep 'registry' | grep '\.tar$' | head -n1 || true)"
if [[ -z "${TAR_FILE}" ]]; then
  err "registry tar file not found in current directory"
  exit 1
fi

REGISTRY_TAG="$(echo "${TAR_FILE}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
if [[ -z "${REGISTRY_TAG}" ]]; then
  err "failed to extract registry tag from tar file: ${TAR_FILE}"
  exit 1
fi

if command -v getenforce >/dev/null 2>&1; then
  SELINUX_MODE="$(getenforce)"
else
  SELINUX_MODE="Disabled"
fi

log "loading image tar: ${TAR_FILE}"
podman load --input "${TAR_FILE}"

if ! podman image exists "${BASE_REGISTRY_IMAGE}:${REGISTRY_TAG}"; then
  err "image not found after load: ${BASE_REGISTRY_IMAGE}:${REGISTRY_TAG}"
  exit 1
fi

for REGISTRY in "${REGISTRIES[@]}"; do
  IFS=':' read -r NAME DIR HOST_PORT <<< "${REGISTRY}"

  if [[ -z "${NAME}" || -z "${DIR}" || -z "${HOST_PORT}" ]]; then
    err "invalid registry definition: ${REGISTRY}"
    exit 1
  fi

  if ss -lnt "( sport = :${HOST_PORT} )" | grep -q ":${HOST_PORT}"; then
    if ! podman container exists "${NAME}"; then
      err "port ${HOST_PORT} already in use and container ${NAME} does not exist"
      exit 1
    fi
  fi

  log "preparing directories for ${NAME}"
  mkdir -p "${DIR}/data" "${DIR}/certs" "${DIR}/auth"

  cp -f "${CERT_DIR}/${CERT_FILE}" "${DIR}/certs/${CERT_FILE}"
  cp -f "${CERT_DIR}/${KEY_FILE}" "${DIR}/certs/${KEY_FILE}"

  if podman container exists "${NAME}"; then
    log "removing existing container ${NAME}"
    podman rm -f "${NAME}"
  fi

  if [[ -f "/etc/systemd/system/${NAME}.service" ]]; then
    systemctl disable --now "${NAME}.service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${NAME}.service"
  fi

  log "starting container ${NAME} on port ${HOST_PORT}"

  if [[ "${SELINUX_MODE}" == "Disabled" ]]; then
    podman run -d \
      --name "${NAME}" \
      -p "${HOST_PORT}:${REGISTRY_CONTAINER_PORT}" \
      -v "${DIR}/data:/var/lib/registry" \
      -v "${DIR}/certs:/certs" \
      -v /etc/hosts:/etc/hosts \
      -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${CERT_FILE}" \
      -e REGISTRY_HTTP_TLS_KEY="/certs/${KEY_FILE}" \
      "${BASE_REGISTRY_IMAGE}:${REGISTRY_TAG}"
  else
    podman run -d \
      --name "${NAME}" \
      -p "${HOST_PORT}:${REGISTRY_CONTAINER_PORT}" \
      -v "${DIR}/data:/var/lib/registry:z" \
      -v "${DIR}/certs:/certs:z" \
      -v /etc/hosts:/etc/hosts:z \
      -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${CERT_FILE}" \
      -e REGISTRY_HTTP_TLS_KEY="/certs/${KEY_FILE}" \
      "${BASE_REGISTRY_IMAGE}:${REGISTRY_TAG}"
  fi

  log "generating systemd unit for ${NAME}"
  podman generate systemd --name "${NAME}" > "/etc/systemd/system/${NAME}.service"
done

systemctl daemon-reload

for REGISTRY in "${REGISTRIES[@]}"; do
  IFS=':' read -r NAME DIR HOST_PORT <<< "${REGISTRY}"
  log "enabling service ${NAME}.service"
  systemctl enable --now "${NAME}.service"
done

podman ps
echo

for REGISTRY in "${REGISTRIES[@]}"; do
  IFS=':' read -r NAME DIR HOST_PORT <<< "${REGISTRY}"
  log "health check: ${NAME}"
  curl -sk -o /dev/null -w "%{http_code}\n" "https://${HOST}.${CLUSTER}.${DOMAIN}:${HOST_PORT}/v2/"
done
