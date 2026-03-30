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

FCOS_KERNEL_SOURCE="${FCOS_KERNEL_SOURCE:-}"
FCOS_INITRAMFS_SOURCE="${FCOS_INITRAMFS_SOURCE:-}"
FCOS_ROOTFS_SOURCE="${FCOS_ROOTFS_SOURCE:-}"

FCOS_KERNEL_TARGET="${FCOS_KERNEL_TARGET:-${TFTP_ROOT}/fedora-coreos-live-kernel-x86_64}"
FCOS_INITRAMFS_TARGET="${FCOS_INITRAMFS_TARGET:-${TFTP_ROOT}/fedora-coreos-live-initramfs.x86_64.img}"
FCOS_ROOTFS_TARGET="${FCOS_ROOTFS_TARGET:-${HTTP_ROOT}/fedora-coreos-live-rootfs.x86_64.img}"

main() {
  require_root

  [[ -f "${INSTALL_WORKDIR}/bootstrap.ign" ]] || die "bootstrap.ign not found"
  [[ -f "${INSTALL_WORKDIR}/master.ign" ]] || die "master.ign not found"
  [[ -f "${INSTALL_WORKDIR}/worker.ign" ]] || die "worker.ign not found"

  [[ -n "${FCOS_KERNEL_SOURCE}" && -f "${FCOS_KERNEL_SOURCE}" ]] || die "FCOS_KERNEL_SOURCE not found"
  [[ -n "${FCOS_INITRAMFS_SOURCE}" && -f "${FCOS_INITRAMFS_SOURCE}" ]] || die "FCOS_INITRAMFS_SOURCE not found"
  [[ -n "${FCOS_ROOTFS_SOURCE}" && -f "${FCOS_ROOTFS_SOURCE}" ]] || die "FCOS_ROOTFS_SOURCE not found"

  ensure_dir "${HTTP_ROOT}"
  ensure_dir "${TFTP_ROOT}"
  ensure_dir "${IGNITION_HTTP_DIR}"

  cp -f "${INSTALL_WORKDIR}/bootstrap.ign" "${IGNITION_HTTP_DIR}/bootstrap.ign"
  cp -f "${INSTALL_WORKDIR}/master.ign" "${IGNITION_HTTP_DIR}/master.ign"
  cp -f "${INSTALL_WORKDIR}/worker.ign" "${IGNITION_HTTP_DIR}/worker.ign"

  cp -f "${FCOS_KERNEL_SOURCE}" "${FCOS_KERNEL_TARGET}"
  cp -f "${FCOS_INITRAMFS_SOURCE}" "${FCOS_INITRAMFS_TARGET}"
  cp -f "${FCOS_ROOTFS_SOURCE}" "${FCOS_ROOTFS_TARGET}"

  chmod 0644 \
    "${IGNITION_HTTP_DIR}/bootstrap.ign" \
    "${IGNITION_HTTP_DIR}/master.ign" \
    "${IGNITION_HTTP_DIR}/worker.ign" \
    "${FCOS_KERNEL_TARGET}" \
    "${FCOS_INITRAMFS_TARGET}" \
    "${FCOS_ROOTFS_TARGET}"

  log "published ignition and FCOS artifacts"
}

main "$@"
