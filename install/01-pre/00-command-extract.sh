#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"

DEST_DIR="${DEST_DIR:-/usr/local/bin}"
TAR_DIR="${TAR_DIR:-${SCRIPT_DIR}}"

INSTALL_TARGETS=(
  "helm-*-linux-amd64.tar.gz:linux-amd64/helm:helm"
  "openshift-client-linux-amd64-*.tar.gz:oc:oc"
  "openshift-client-linux-amd64-*.tar.gz:kubectl:kubectl"
  "openshift-install-linux-*.tar.gz:openshift-install:openshift-install"
)

find_tar_file() {
  local pattern="$1"
  local tar_file

  tar_file="$(find "${TAR_DIR}" -maxdepth 1 -type f -name "${pattern}" | sort | tail -n1 || true)"
  [[ -n "${tar_file}" ]] || die "tar file not found in ${TAR_DIR} for pattern: ${pattern}"

  echo "${tar_file}"
}

install_from_tar() {
  local tar_file="$1"
  local member_path="$2"
  local bin_name="$3"

  tar tf "${tar_file}" | grep -qx "${member_path}" || die "member not found in ${tar_file}: ${member_path}"

  log "installing ${bin_name} from ${tar_file}"
  tar xf "${tar_file}" -O "${member_path}" > "${DEST_DIR}/${bin_name}"
  chmod 0755 "${DEST_DIR}/${bin_name}"
}

verify_installed_binaries() {
  [[ -x "${DEST_DIR}/helm" ]] || die "helm not installed"
  [[ -x "${DEST_DIR}/oc" ]] || die "oc not installed"
  [[ -x "${DEST_DIR}/kubectl" ]] || die "kubectl not installed"
  [[ -x "${DEST_DIR}/openshift-install" ]] || die "openshift-install not installed"

  "${DEST_DIR}/helm" version --short >/dev/null 2>&1 || true
  "${DEST_DIR}/oc" version --client >/dev/null 2>&1 || true
  "${DEST_DIR}/kubectl" version --client >/dev/null 2>&1 || true
  "${DEST_DIR}/openshift-install" version >/dev/null 2>&1 || true
}

main() {
  require_root
  require_cmd tar

  ensure_dir "${DEST_DIR}"

  local target tar_pattern member_path bin_name tar_file
  for target in "${INSTALL_TARGETS[@]}"; do
    IFS=':' read -r tar_pattern member_path bin_name <<< "${target}"
    tar_file="$(find_tar_file "${tar_pattern}")"
    install_from_tar "${tar_file}" "${member_path}" "${bin_name}"
  done

  verify_installed_binaries

  log "installed files"
  ls -l \
    "${DEST_DIR}/helm" \
    "${DEST_DIR}/oc" \
    "${DEST_DIR}/kubectl" \
    "${DEST_DIR}/openshift-install"
}

main "$@"
