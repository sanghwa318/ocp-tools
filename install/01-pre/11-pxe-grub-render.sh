#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/network.env"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

TFTP_ROOT="${TFTP_ROOT:-/tftpboot}"
PXELINUX_DIR="${PXELINUX_DIR:-${TFTP_ROOT}/pxelinux.cfg}"
GRUBCFG_DIR="${GRUBCFG_DIR:-${TFTP_ROOT}}"
HTTP_ROOT="${HTTP_ROOT:-/var/www/html}"

COS_SOURCE_DIR="${COS_SOURCE_DIR:-${INSTALL_DIR}/cos}"
COS_KERNEL_MATCH="${COS_KERNEL_MATCH:-kernel}"
COS_INITRAMFS_MATCH="${COS_INITRAMFS_MATCH:-initramfs}"
COS_ROOTFS_MATCH="${COS_ROOTFS_MATCH:-rootfs}"

IGNITION_HTTP_HOST="${IGNITION_HTTP_HOST:-${HOST}.${CLUSTER_NAME}.${BASE_DOMAIN}}"
IGNITION_HTTP_PORT="${IGNITION_HTTP_PORT:-8080}"
IGNITION_BASE_URL="${IGNITION_BASE_URL:-http://${IGNITION_HTTP_HOST}:${IGNITION_HTTP_PORT}}"

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

get_bastion_count() {
  awk '
    BEGIN { FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    $2 == "bastion" { count++ }
    END { print count+0 }
  ' "${INVENTORY_FILE}"
}

get_effective_nameserver() {
  local bastion_count
  bastion_count="$(get_bastion_count)"

  if [[ "${bastion_count}" -lt 2 ]]; then
    echo "${PXE_BASTION_IP}"
  else
    echo "${DNS_SERVER}"
  fi
}

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

short_hostname() {
  local fqdn="$1"
  echo "${fqdn%%.*}"
}

build_network_args() {
  local hostname="$1"
  local ip="$2"
  local gateway="$3"
  local nic="$4"
  local nettype="$5"
  local vlan_id="$6"
  local effective_nameserver="$7"

  case "${nettype}" in
    ethernet)
      echo "ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:${nic}:none nameserver=${effective_nameserver}"
      ;;
    vlan)
      echo "vlan=${nic}.${vlan_id}:${nic} ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:${nic}.${vlan_id}:none nameserver=${effective_nameserver}"
      ;;
    bond)
      echo "bond=bond0:${nic}:mode=active-backup,miimon=100 ip=${ip}::${gateway}:${PXE_NETMASK}:${hostname}:bond0:none nameserver=${effective_nameserver}"
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
  local kernel_file="$6"
  local initramfs_file="$7"
  local rootfs_url="$8"

  cat > "${outfile}" <<EOF
DEFAULT 1
LABEL 1
MENU LABEL ${nodename}
     KERNEL ${kernel_file}
     APPEND initrd=${initramfs_file} coreos.live.rootfs_url=${rootfs_url} coreos.inst.install_dev=${install_dev} coreos.inst.ignition_url=${IGNITION_BASE_URL}/${role}.ign ${network_args}
EOF
}

write_grub_file() {
  local outfile="$1"
  local nodename="$2"
  local role="$3"
  local install_dev="$4"
  local network_args="$5"
  local kernel_file="$6"
  local initramfs_file="$7"
  local rootfs_url="$8"

  cat > "${outfile}" <<EOF
set default="0"
menuentry '${nodename}' {
     linux ${kernel_file} nomodeset rd.neednet=1 ${network_args} coreos.inst=yes coreos.inst.install_dev=${install_dev} coreos.live.rootfs_url=${rootfs_url} coreos.inst.ignition_url=${IGNITION_BASE_URL}/${role}.ign
     initrd ${initramfs_file}
}
EOF
}

main() {
  require_root
  require_cmd find
  require_cmd grep
  require_cmd basename

  [[ -f "${INVENTORY_FILE}" ]] || die "inventory file not found: ${INVENTORY_FILE}"
  [[ -d "${COS_SOURCE_DIR}" ]] || die "COS source directory not found: ${COS_SOURCE_DIR}"

  ensure_dir "${PXELINUX_DIR}"
  ensure_dir "${GRUBCFG_DIR}"

  local kernel_path initramfs_path rootfs_path
  local kernel_file initramfs_file rootfs_file rootfs_url
  local effective_nameserver

  kernel_path="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_KERNEL_MATCH}")"
  initramfs_path="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_INITRAMFS_MATCH}")"
  rootfs_path="$(find_single_cos_file "${COS_SOURCE_DIR}" "${COS_ROOTFS_MATCH}")"

  kernel_file="$(basename "${kernel_path}")"
  initramfs_file="$(basename "${initramfs_path}")"
  rootfs_file="$(basename "${rootfs_path}")"
  rootfs_url="http://${IGNITION_HTTP_HOST}:${IGNITION_HTTP_PORT}/${rootfs_file}"

  effective_nameserver="$(get_effective_nameserver)"

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
    local_network_args="$(build_network_args "${hostname}" "${ip}" "${gateway}" "${nic}" "${nettype}" "${vlan_id}" "${effective_nameserver}")"
    local_shortname="$(short_hostname "${hostname}")"

    write_pxelinux_file "${PXELINUX_DIR}/${local_mac}" "${local_shortname}" "${role}" "${local_install_dev}" "${local_network_args}" "${kernel_file}" "${initramfs_file}" "${rootfs_url}"
    write_grub_file "${GRUBCFG_DIR}/grub.cfg-${local_mac}" "${local_shortname}" "${role}" "${local_install_dev}" "${local_network_args}" "${kernel_file}" "${initramfs_file}" "${rootfs_url}"
  done < "${INVENTORY_FILE}"

  log "generated PXE and GRUB configs"
  log "kernel file: ${kernel_file}"
  log "initramfs file: ${initramfs_file}"
  log "rootfs file: ${rootfs_file}"
  log "effective nameserver: ${effective_nameserver}"
}

main "$@"
