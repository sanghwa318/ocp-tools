#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"

DEST_DIR="${DEST_DIR:-/usr/local/bin}"
TAR_DIR="${TAR_DIR:-${SCRIPT_DIR}}"

INSTALL_TARGETS=(
  "helm-*-linux-amd64.tar.gz:helm"
  "openshift-client-linux-amd64-*.tar.gz:oc"
  "openshift-client-linux-amd64-*.tar.gz:kubectl"
  "openshift-install-linux-*.tar.gz:openshift-install"
)

find_tar_file() {
  local pattern="$1"
  local tar_file

  tar_file="$(find "${TAR_DIR}" -maxdepth 1 -type f -name "${pattern}" | sort | tail -n1 || true)"
  [[ -n "${tar_file}" ]] || die "tar file not found in ${TAR_DIR} for pattern: ${pattern}"

  echo "${tar_file}"
}

extract_expected_version_from_tar_name() {
  local tar_file="$1"
  local base

  base="$(basename "${tar_file}")"

  if [[ "${base}" =~ ^helm-v([0-9]+\.[0-9]+\.[0-9]+)-linux-amd64\.tar\.gz$ ]]; then
    echo "v${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "${base}" =~ ^helm-([0-9]+\.[0-9]+\.[0-9]+)-linux-amd64\.tar\.gz$ ]]; then
    echo "v${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "${base}" =~ ^openshift-client-linux-amd64-.*-([0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9._-]+)\.tar\.gz$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "${base}" =~ ^openshift-install-linux-([0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9._-]+)\.tar\.gz$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  die "failed to detect expected version from tar file name: ${tar_file}"
}

get_installed_version() {
  local bin_path="$1"
  local bin_name="$2"
  local out version

  [[ -x "${bin_path}" ]] || return 1

  case "${bin_name}" in
    helm)
      out="$("${bin_path}" version --short 2>/dev/null || true)"
      version="$(printf '%s\n' "${out}" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
      ;;
    oc)
      out="$("${bin_path}" version 2>/dev/null || true)"
      version="$(printf '%s\n' "${out}" | sed -n 's/^Client Version: v\{0,1\}\(.*\)$/\1/p' | head -n1)"
      ;;
    kubectl)
      out="$("${bin_path}" version --client=true 2>/dev/null || true)"
      version="$(printf '%s\n' "${out}" | sed -n 's/^Client Version: v\{0,1\}\(.*\)$/\1/p' | head -n1)"
      if [[ -z "${version}" ]]; then
        version="$(printf '%s\n' "${out}" | sed -n 's/.*GitVersion:"v\([^"]*\)".*/\1/p' | head -n1)"
      fi
      ;;
    openshift-install)
      out="$("${bin_path}" version 2>/dev/null || true)"
      version="$(printf '%s\n' "${out}" | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9._-]+' | head -n1 || true)"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -n "${version}" ]] || return 1
  echo "${version}"
}

should_skip_install() {
  local tar_file="$1"
  local bin_name="$2"
  local dest_path="${DEST_DIR}/${bin_name}"
  local expected_version installed_version

  [[ -x "${dest_path}" ]] || return 1

  expected_version="$(extract_expected_version_from_tar_name "${tar_file}")"
  installed_version="$(get_installed_version "${dest_path}" "${bin_name}" || true)"

  [[ -n "${installed_version}" ]] || return 1
  [[ "${installed_version}" == "${expected_version}" ]]
}

install_single_binary_from_tar() {
  local tar_file="$1"
  local bin_name="$2"
  local tmp_dir tmp_file member_path

  if should_skip_install "${tar_file}" "${bin_name}"; then
    log "skip ${bin_name}: already installed with matching version"
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  member_path="$(tar tf "${tar_file}" | grep -x "${bin_name}" | head -n1 || true)"

  if [[ -z "${member_path}" ]]; then
    member_path="$(tar tf "${tar_file}" | awk -F/ -v name="${bin_name}" '$NF == name { print; exit }' || true)"
  fi

  [[ -n "${member_path}" ]] || {
    rm -rf "${tmp_dir}"
    die "member not found in ${tar_file}: ${bin_name}"
  }

  log "installing ${bin_name} from ${tar_file} (${member_path})"
  tar xf "${tar_file}" -C "${tmp_dir}" "${member_path}"

  [[ -f "${tmp_dir}/${member_path}" ]] || {
    rm -rf "${tmp_dir}"
    die "extracted path is not a regular file: ${member_path}"
  }

  [[ -s "${tmp_dir}/${member_path}" ]] || {
    rm -rf "${tmp_dir}"
    die "extracted file is empty: ${member_path}"
  }

  tmp_file="$(mktemp "${DEST_DIR}/.${bin_name}.XXXXXX")"
  rm -f "${tmp_file}"
  cp -f "${tmp_dir}/${member_path}" "${tmp_file}"
  chmod 0755 "${tmp_file}"
  mv -f "${tmp_file}" "${DEST_DIR}/${bin_name}"

  rm -rf "${tmp_dir}"
}

install_openshift_client_tar() {
  local tar_file="$1"
  local expected_version
  local tmp_dir
  local tmp_oc tmp_kubectl

  expected_version="$(extract_expected_version_from_tar_name "${tar_file}")"

  if [[ -x "${DEST_DIR}/oc" && -x "${DEST_DIR}/kubectl" ]]; then
    local oc_version kubectl_version
    oc_version="$(get_installed_version "${DEST_DIR}/oc" oc || true)"
    kubectl_version="$(get_installed_version "${DEST_DIR}/kubectl" kubectl || true)"

    if [[ "${oc_version:-}" == "${expected_version}" && "${kubectl_version:-}" == "${expected_version}" ]]; then
      log "skip oc: already installed with matching version"
      log "skip kubectl: already installed with matching version"
      return 0
    fi
  fi

  tmp_dir="$(mktemp -d)"
  log "installing oc and kubectl from ${tar_file}"
  tar xf "${tar_file}" -C "${tmp_dir}" oc kubectl

  [[ -f "${tmp_dir}/oc" && -s "${tmp_dir}/oc" ]] || {
    rm -rf "${tmp_dir}"
    die "failed to extract oc from ${tar_file}"
  }

  [[ -f "${tmp_dir}/kubectl" && -s "${tmp_dir}/kubectl" ]] || {
    rm -rf "${tmp_dir}"
    die "failed to extract kubectl from ${tar_file}"
  }

  tmp_oc="$(mktemp "${DEST_DIR}/.oc.XXXXXX")"
  tmp_kubectl="$(mktemp "${DEST_DIR}/.kubectl.XXXXXX")"
  rm -f "${tmp_oc}" "${tmp_kubectl}"

  cp -f "${tmp_dir}/oc" "${tmp_oc}"
  cp -f "${tmp_dir}/kubectl" "${tmp_kubectl}"
  chmod 0755 "${tmp_oc}" "${tmp_kubectl}"
  mv -f "${tmp_oc}" "${DEST_DIR}/oc"
  mv -f "${tmp_kubectl}" "${DEST_DIR}/kubectl"

  rm -rf "${tmp_dir}"
}

verify_installed_binaries() {
  [[ -x "${DEST_DIR}/helm" ]] || die "helm not installed"
  [[ -x "${DEST_DIR}/oc" ]] || die "oc not installed"
  [[ -x "${DEST_DIR}/kubectl" ]] || die "kubectl not installed"
  [[ -x "${DEST_DIR}/openshift-install" ]] || die "openshift-install not installed"

  "${DEST_DIR}/helm" version --short >/dev/null 2>&1 || true
  "${DEST_DIR}/oc" version >/dev/null 2>&1 || true
  "${DEST_DIR}/kubectl" version --client=true >/dev/null 2>&1 || true
  "${DEST_DIR}/openshift-install" version >/dev/null 2>&1 || true
}

main() {
  require_root
  require_cmd tar
  require_cmd awk
  require_cmd mktemp
  require_cmd cp

  ensure_dir "${DEST_DIR}"

  local helm_tar client_tar install_tar

  helm_tar="$(find_tar_file 'helm-*-linux-amd64.tar.gz')"
  client_tar="$(find_tar_file 'openshift-client-linux-amd64-*.tar.gz')"
  install_tar="$(find_tar_file 'openshift-install-linux-*.tar.gz')"

  install_single_binary_from_tar "${helm_tar}" "helm"
  install_openshift_client_tar "${client_tar}"
  install_single_binary_from_tar "${install_tar}" "openshift-install"

  verify_installed_binaries

  log "installed files"
  ls -l \
    "${DEST_DIR}/helm" \
    "${DEST_DIR}/oc" \
    "${DEST_DIR}/kubectl" \
    "${DEST_DIR}/openshift-install"
}

main "$@"
