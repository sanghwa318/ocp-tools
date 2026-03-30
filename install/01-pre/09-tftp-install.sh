#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"

TFTP_ROOT="${TFTP_ROOT:-/tftpboot}"
TFTP_SERVICE_FILE="${TFTP_SERVICE_FILE:-/etc/systemd/system/tftp.service}"
TFTP_SOCKET_NAME="${TFTP_SOCKET_NAME:-tftp.socket}"

SYSLINUX_DIR="${SYSLINUX_DIR:-/usr/share/syslinux}"
GRUB_EFI_SOURCE="${GRUB_EFI_SOURCE:-/media/EFI/BOOT/grubx64.efi}"
GRUB_EFI_TARGET="${GRUB_EFI_TARGET:-${TFTP_ROOT}/grubx64.efi}"

main() {
  require_root
  require_cmd systemctl

  ensure_dir "${TFTP_ROOT}"
  ensure_dir "${TFTP_ROOT}/pxelinux.cfg"

  [[ -d "${SYSLINUX_DIR}" ]] || die "syslinux directory not found: ${SYSLINUX_DIR}"
  [[ -f "${GRUB_EFI_SOURCE}" ]] || die "grub efi source not found: ${GRUB_EFI_SOURCE}"

  cp -f "${SYSLINUX_DIR}/pxelinux.0" "${TFTP_ROOT}/"
  cp -f "${SYSLINUX_DIR}/menu.c32" "${TFTP_ROOT}/" 2>/dev/null || true
  cp -f "${SYSLINUX_DIR}/libutil.c32" "${TFTP_ROOT}/" 2>/dev/null || true
  cp -f "${SYSLINUX_DIR}/ldlinux.c32" "${TFTP_ROOT}/" 2>/dev/null || true
  cp -f "${GRUB_EFI_SOURCE}" "${GRUB_EFI_TARGET}"
  chmod 0644 "${GRUB_EFI_TARGET}"

  cat > "${TFTP_SERVICE_FILE}" <<'EOF'
[Unit]
Description=Tftp Server
Requires=tftp.socket
Documentation=man:in.tftpd

[Service]
ExecStart=/usr/sbin/in.tftpd -s /tftpboot
StandardInput=socket

[Install]
Also=tftp.socket
EOF

  systemctl daemon-reload
  systemctl enable --now "${TFTP_SOCKET_NAME}"
  systemctl status "${TFTP_SOCKET_NAME}" --no-pager || true

  log "tftp configured"
}

main "$@"
