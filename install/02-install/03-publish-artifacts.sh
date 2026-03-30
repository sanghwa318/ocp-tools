#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"
IGNITION_HTTP_DIR="${IGNITION_HTTP_DIR:-${HTTP_ROOT}}"
TFTP_ROOT="${TFTP_ROOT:-/tftpboot}"

COS_SOURCE_DIR="${COS_SOURCE_DIR:-${INSTALL_DIR}/cos}"

COS_KERNEL_MATCH="${COS_KERNEL_MATCH:-kernel}"
COS_INITRAMFS_MATCH="${COS_INITRAMFS_MATCH:-initramfs}"
COS_ROOTFS_MATCH="${COS_ROOTFS_MATCH:-rootfs}"

find_single_cos_file() {
  local source_dir="$1"
  local match_string="$2"
  local found

  found="$(find "${source_dir}" -maxdepth 1 -type f | grep -i "${match_string}" | sort || true)"

  [[ -n "${found}" ]] || die "no COS file matched '${match_string}' in ${source_dir}"

  if [[ "$(printf '%s\n' "${found}" | sed '/^$/d' | wc -l | awk '{print $1}')" -ne 1 ]]; then
    err "multiple COS files matched '${match_string}' in ${source_dir}:"
    printf '%s\n' "${found}" >&2
    die "expected exactly one match for '${match_string}'"
  fi

  printf '%s\n' "${found}" | head -n1
}

main() {
  require_root
  require_cmd find
  require_cmd grep
  require_cmd basename

  [[ -f "${INSTALL_WORKDIR}/bootstrap.ign" ]] || die "bootstrap.ign not found"
  [[ -f "${INSTALL_WORKDIR}/master.ign" ]] || die "master.ign not found"
  [[ -f "${INSTALL_WORKDIR}/worker.ign" ]] || die "worker.ign not found"

  [[ -d "${COS_SOURCE_DIR}" ]] || die "COS source directory not found: ${COS_SOURCE_DIR}"

  local cos_kernel_source
  local cos_initramfs_source
  local cos_rootfs_source

  local cos_kernel_target
  local cos_initramfs_target
  local cos_rootfs_target

  cos_kernel_source="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_KERNEL_MATCH}")"
  cos_initramfs_source="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_INITRAMFS_MATCH}")"
  cos_rootfs_source="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_ROOTFS_MATCH}")"

  cos_kernel_target="${TFTP_ROOT}/$(basename "${cos_kernel_source}")"
  cos_initramfs_target="${TFTP_ROOT}/$(basename "${cos_initramfs_source}")"
  cos_rootfs_target="${HTTP_ROOT}/$(basename "${cos_rootfs_source}")"

  ensure_dir "${HTTP_ROOT}"
  ensure_dir "${TFTP_ROOT}"
  ensure_dir "${IGNITION_HTTP_DIR}"

  cp -f "${INSTALL_WORKDIR}/bootstrap.ign" "${IGNITION_HTTP_DIR}/bootstrap.ign"
  cp -f "${INSTALL_WORKDIR}/master.ign" "${IGNITION_HTTP_DIR}/master.ign"
  cp -f "${INSTALL_WORKDIR}/worker.ign" "${IGNITION_HTTP_DIR}/worker.ign"

  cp -f "${cos_kernel_source}" "${cos_kernel_target}"
  cp -f "${cos_initramfs_source}" "${cos_initramfs_target}"
  cp -f "${cos_rootfs_source}" "${cos_rootfs_target}"

  chmod 0644 \
    "${IGNITION_HTTP_DIR}/bootstrap.ign" \
    "${IGNITION_HTTP_DIR}/master.ign" \
    "${IGNITION_HTTP_DIR}/worker.ign" \
    "${cos_kernel_target}" \
    "${cos_initramfs_target}" \
    "${cos_rootfs_target}"

  log "published ignition and COS artifacts"
  log "COS kernel source: ${cos_kernel_source}"
  log "COS initramfs source: ${cos_initramfs_source}"
  log "COS rootfs source: ${cos_rootfs_source}"
  log "COS kernel target: ${cos_kernel_target}"
  log "COS initramfs target: ${cos_initramfs_target}"
  log "COS rootfs target: ${cos_rootfs_target}"
}

main "$@"
