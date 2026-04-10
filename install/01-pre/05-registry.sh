#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/registry.env"

parse_registries() {
  IFS=',' read -ra REGISTRY_ITEMS <<< "${REGISTRIES_CSV}"
}

find_registry_tar() {
  if [[ -n "${REGISTRY_TAR_FILE}" && -f "${REGISTRY_TAR_FILE}" ]]; then
    echo "${REGISTRY_TAR_FILE}"
    return 0
  fi

  local tar_file
  tar_file="$(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '*registry*.tar*' | sort | head -n1 || true)"
  [[ -n "${tar_file}" ]] || die "registry tar file not found"
  echo "${tar_file}"
}

detect_registry_tag() {
  local tar_file="$1"

  if [[ -n "${REGISTRY_TAG}" ]]; then
    echo "${REGISTRY_TAG}"
    return 0
  fi

  local tag
  tag="$(basename "${tar_file}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  [[ -n "${tag}" ]] || die "failed to detect registry tag from ${tar_file}"
  echo "${tag}"
}

main() {
  require_root
  require_cmd podman
  require_cmd systemctl
  require_cmd ss

  [[ -f "${CERT_DIR}/${CERT_FILE}" ]] || die "certificate file not found: ${CERT_DIR}/${CERT_FILE}"
  [[ -f "${CERT_DIR}/${KEY_FILE}" ]] || die "key file not found: ${CERT_DIR}/${KEY_FILE}"

  local tar_file tag
  tar_file="$(find_registry_tar)"
  tag="$(detect_registry_tag "${tar_file}")"

  podman load --input "${tar_file}"
  sleep 3s
  podman image exists "${BASE_REGISTRY_IMAGE}:${tag}" || die "image not found after load"

  parse_registries

  local item
  for item in "${REGISTRY_ITEMS[@]}"; do
    IFS='|' read -r NAME DIR HOST_PORT <<< "${item}"
    [[ -n "${NAME}" && -n "${DIR}" && -n "${HOST_PORT}" ]] || die "invalid registry item: ${item}"

    ensure_dir "${DIR}/data"
    ensure_dir "${DIR}/certs"
    ensure_dir "${DIR}/auth"

    cp -f "${CERT_DIR}/${CERT_FILE}" "${DIR}/certs/${CERT_FILE}"
    cp -f "${CERT_DIR}/${KEY_FILE}" "${DIR}/certs/${KEY_FILE}"

    if ss -lnt "( sport = :${HOST_PORT} )" | grep -q ":${HOST_PORT}"; then
      if ! podman container exists "${NAME}"; then
        die "port ${HOST_PORT} already in use and container ${NAME} does not exist"
      fi
    fi

    if podman container exists "${NAME}"; then
      log "removing existing container ${NAME}"
      podman rm -f "${NAME}" || true
    fi

    if [[ -f "/etc/systemd/system/${NAME}.service" ]]; then
      systemctl disable --now "${NAME}.service" >/dev/null 2>&1 || true
      rm -f "/etc/systemd/system/${NAME}.service"
    fi

    podman run -d \
      --name "${NAME}" \
      -p "${HOST_PORT}:${REGISTRY_CONTAINER_PORT}" \
      -v "${DIR}/data:/var/lib/registry:z" \
      -v "${DIR}/certs:/certs:z" \
      -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${CERT_FILE}" \
      -e REGISTRY_HTTP_TLS_KEY="/certs/${KEY_FILE}" \
      "${BASE_REGISTRY_IMAGE}:${tag}"

    podman generate systemd --name "${NAME}" > "/etc/systemd/system/${NAME}.service"
  done

  systemctl daemon-reload

  for item in "${REGISTRY_ITEMS[@]}"; do
    IFS='|' read -r NAME DIR HOST_PORT <<< "${item}"
    systemctl enable --now "${NAME}.service"
    systemctl is-enabled "${NAME}.service" >/dev/null
    systemctl is-active "${NAME}.service" >/dev/null
    log "${NAME} enabled and started"
  done

  podman ps
}

main "$@"
