#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

TFTP_ROOT="${TFTP_ROOT:-/tftpboot}"
PXELINUX_DIR="${PXELINUX_DIR:-${TFTP_ROOT}/pxelinux.cfg}"
GRUBCFG_DIR="${GRUBCFG_DIR:-${TFTP_ROOT}}"

FCOS_KERNEL_FILE="${FCOS_KERNEL_FILE:-fedora-coreos-live-kernel-x86_64}"
FCOS_INITRAMFS_FILE="${FCOS_INITRAMFS_FILE:-fedora-coreos-live-initramfs.x86_64.img}"
FCOS_ROOTFS_URL="${FCOS_ROOTFS_URL:-http://${PXE_BASTION_IP}:8080/fedora-coreos-live-rootfs.x86_64.img}"
IGNITION_BASE_URL="${IGNITION_BASE_URL:-http://${PXE_BASTION_IP}:8080}"

mac_to_pxe_name() {
  local mac="$1"
  echo "01-$(echo "${mac}" | tr '[:upper:]' '[:lower:]' | sed 's/:/-/g')"
}

get_install_dev() {
  local role="$1"
  local install_dev="$2"

  if [[ "${install_dev}" != "-" && -n "${install_dev}" ]]; then
    echo "${install_dev}"
    return 0
  fi

  case "${role}" in
    bootstrap|master) echo "/dev/vda" ;;
    worker|infra) echo "/dev/sda" ;;
    *) echo "/dev/vda" ;;
  esac
}

normalize_role() {
  local role="$1"
  if [[ "${role}" == "infra" ]]; then
    echo "worker"
  else
    echo "${role}"
  fi
}

build_network_args() {
  local hostname="$1"
  local ip="$2"
  local gateway="$3"
  local nic="$4"
  local nettype="$5"
  local vlan_id="$6"

  case "${nettype}" in
    ethernet)
      echo "ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:${nic}:none nameserver=${DNS_SERVER}"
      ;;
    vlan)
      echo "vlan=${nic}.${vlan_id}:${nic} ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:${nic}.${vlan_id}:none nameserver=${DNS_SERVER}"
      ;;
    bond)
      echo "bond=bond0:${nic}:mode=active-backup,miimon=100 ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:bond0:none nameserver=${DNS_SERVER}"
      ;;
    *)
      die "unsupported nettype: ${nettype}"
      ;;
  esac
}

write_pxelinux_file() {
  local outfile="$1"
  local nodename="$2"
  local role="$3"
  local install_dev="$4"
  local network_args="$5"

  cat > "${outfile}" <<EOF
DEFAULT 1
LABEL 1
MENU LABEL ${nodename}
     KERNEL ${FCOS_KERNEL_FILE}
     APPEND initrd=${FCOS_INITRAMFS_FILE} coreos.live.rootfs_url=${FCOS_ROOTFS_URL} coreos.inst.install_dev=${install_dev} coreos.inst.ignition_url=${IGNITION_BASE_URL}/${role}.ign ${network_args}
EOF
}

write_grub_file() {
  local outfile="$1"
  local nodename="$2"
  local role="$3"
  local install_dev="$4"
  local network_args="$5"

  cat > "${outfile}" <<EOF
set default="0"
menuentry '${nodename}' {
     linux ${FCOS_KERNEL_FILE} nomodeset rd.neednet=1 ${network_args} coreos.inst=yes coreos.inst.install_dev=${install_dev} coreos.live.rootfs_url=${FCOS_ROOTFS_URL} coreos.inst.ignition_url=${IGNITION_BASE_URL}/${role}.ign
     initrd ${FCOS_INITRAMFS_FILE}
}
EOF
}

main() {
  require_root
  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"

  ensure_dir "${PXELINUX_DIR}"
  ensure_dir "${GRUBCFG_DIR}"

  rm -f "${PXELINUX_DIR}"/01-* || true
  rm -f "${GRUBCFG_DIR}"/grub.cfg-01-* || true

  while read -r hostname role ip gateway nic mac nettype vlan_id install_dev; do
    [[ -z "${hostname}" || "${hostname}" =~ ^# ]] && continue

    role="$(normalize_role "${role}")"

    case "${role}" in
      bootstrap|master|worker)
        ;;
      *)
        continue
        ;;
    esac

    local_mac="$(mac_to_pxe_name "${mac}")"
    local_install_dev="$(get_install_dev "${role}" "${install_dev}")"
    local_network_args="$(build_network_args "${hostname}" "${ip}" "${gateway}" "${nic}" "${nettype}" "${vlan_id}")"

    write_pxelinux_file "${PXELINUX_DIR}/${local_mac}" "${hostname}" "${role}" "${local_install_dev}" "${local_network_args}"
    write_grub_file "${GRUBCFG_DIR}/grub.cfg-${local_mac}" "${hostname}" "${role}" "${local_install_dev}" "${local_network_args}"
  done < "${INVENTORY_FILE}"

  log "generated PXE and GRUB configs"
}

main "$@"
