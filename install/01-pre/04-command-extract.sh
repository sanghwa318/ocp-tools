#!/bin/bash
set -euo pipefail

DEST_DIR='/usr/local/bin'

# Default: use the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_DIR="${TAR_DIR:-${SCRIPT_DIR}}"

INSTALL_TARGETS=(
  "helm-*-linux-amd64.tar.gz:linux-amd64/helm:helm"
  "openshift-client-linux-amd64-*.tar.gz:oc:oc"
  "openshift-client-linux-amd64-*.tar.gz:kubectl:kubectl"
  "openshift-install-linux-*.tar.gz:openshift-install:openshift-install"
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

# Find tar file in TAR_DIR using pattern
find_tar_file() {
  local pattern="$1"
  local tar_file

  tar_file="$(find "${TAR_DIR}" -maxdepth 1 -type f -name "${pattern}" | sort | head -n1 || true)"

  if [[ -z "${tar_file}" ]]; then
    err "tar file not found in ${TAR_DIR} for pattern: ${pattern}"
    exit 1
  fi

  echo "${tar_file}"
}

# Extract a specific file from tar and install to DEST_DIR
install_from_tar() {
  local tar_file="$1"
  local member_path="$2"
  local bin_name="$3"

  if ! tar tf "${tar_file}" | grep -qx "${member_path}"; then
    err "member not found in ${tar_file}: ${member_path}"
    exit 1
  fi

  log "installing ${bin_name} from ${tar_file}"
  tar xf "${tar_file}" -O "${member_path}" > "${DEST_DIR}/${bin_name}"
  chmod 0755 "${DEST_DIR}/${bin_name}"
}

main() {
  require_root
  mkdir -p "${DEST_DIR}"

  log "tar directory: ${TAR_DIR}"

  for target in "${INSTALL_TARGETS[@]}"; do
    IFS=':' read -r tar_pattern member_path bin_name <<< "${target}"

    TAR_FILE="$(find_tar_file "${tar_pattern}")"
    install_from_tar "${TAR_FILE}" "${member_path}" "${bin_name}"
  done

  log "installed files"
  ls -l \
    "${DEST_DIR}/helm" \
    "${DEST_DIR}/oc" \
    "${DEST_DIR}/kubectl" \
    "${DEST_DIR}/openshift-install"
}

main "$@"
