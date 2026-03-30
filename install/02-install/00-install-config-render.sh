#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/registry.env"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

INSTALL_CONFIG_TEMPLATE="${TEMPLATE_DIR}/install-config.yaml.tmpl"

indent_file_two_spaces() {
  sed 's/^/  /' "$1"
}
check_existing_install_artifacts() {
  [[ ! -d "${INSTALL_WORKDIR}/manifests" ]] || die "manifests directory already exists: ${INSTALL_WORKDIR}/manifests"
  [[ ! -d "${INSTALL_WORKDIR}/openshift" ]] || die "openshift directory already exists: ${INSTALL_WORKDIR}/openshift"
  [[ ! -d "${INSTALL_WORKDIR}/auth" ]] || die "auth directory already exists: ${INSTALL_WORKDIR}/auth"
  [[ ! -f "${INSTALL_WORKDIR}/bootstrap.ign" ]] || die "bootstrap.ign already exists: ${INSTALL_WORKDIR}/bootstrap.ign"
  [[ ! -f "${INSTALL_WORKDIR}/master.ign" ]] || die "master.ign already exists: ${INSTALL_WORKDIR}/master.ign"
  [[ ! -f "${INSTALL_WORKDIR}/worker.ign" ]] || die "worker.ign already exists: ${INSTALL_WORKDIR}/worker.ign"
}

resolve_pull_secret_file() {
  local root_file="/root/pull-secret.json"
  local install_file="${INSTALL_DIR}/pull-secret.json"
  local registry_auth_host

  registry_auth_host="${REGISTRY_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}:5000"

  if [[ -f "${root_file}" ]]; then
    echo "${root_file}"
    return 0
  fi

  if [[ -f "${install_file}" ]]; then
    echo "${install_file}"
    return 0
  fi

  cat > "${install_file}" <<EOF
{"auths":{"${registry_auth_host}":{"auth":"YWRtaW46YWRtaW4="}}}
EOF

  echo "[INFO] generated default pull secret: ${install_file}" >&2
  echo "${install_file}"
}

resolve_trust_bundle_file() {
  local explicit_file="${ADDITIONAL_TRUST_BUNDLE_FILE:-}"
  local cert_file="${CERT_DIR}/${CERT_FILE}"

  if [[ -n "${explicit_file}" && -f "${explicit_file}" ]]; then
    echo "${explicit_file}"
    return 0
  fi

  if [[ -f "${cert_file}" ]]; then
    echo "${cert_file}"
    return 0
  fi

  die "additional trust bundle file not found and cert file not found: ${cert_file}"
}

main() {
  require_root
  require_cmd sed
  require_cmd awk

  [[ -f "${INSTALL_CONFIG_TEMPLATE}" ]] || die "template not found: ${INSTALL_CONFIG_TEMPLATE}"

  if [[ -e "${INSTALL_WORKDIR}" ]]; then
    die "install workdir already exists: ${INSTALL_WORKDIR}"
  fi

  PULL_SECRET_FILE="$(resolve_pull_secret_file)"
  TRUST_BUNDLE_FILE="$(resolve_trust_bundle_file)"

  [[ -f "${PULL_SECRET_FILE}" ]] || die "pull secret file not found: ${PULL_SECRET_FILE}"
  [[ -f "${SSH_PUBKEY_FILE}" ]] || die "ssh pubkey file not found: ${SSH_PUBKEY_FILE}"
  [[ -f "${TRUST_BUNDLE_FILE}" ]] || die "additional trust bundle file not found: ${TRUST_BUNDLE_FILE}"

  ensure_dir "${INSTALL_BASE_DIR}"
  ensure_dir "${INSTALL_WORKDIR}"
  check_existing_install_artifacts

  local pull_secret
  local ssh_pubkey
  local trust_bundle
  local tmp_render

  pull_secret="$(tr -d '\n' < "${PULL_SECRET_FILE}" | sed 's/[&/\]/\\&/g')"
  ssh_pubkey="$(tr -d '\n' < "${SSH_PUBKEY_FILE}" | sed 's/[&/\]/\\&/g')"
  trust_bundle="$(indent_file_two_spaces "${TRUST_BUNDLE_FILE}")"

  tmp_render="$(mktemp)"

  sed \
    -e "s|@@BASE_DOMAIN@@|${BASE_DOMAIN}|g" \
    -e "s|@@CLUSTER_NAME@@|${CLUSTER_NAME}|g" \
    -e "s|@@CONTROL_PLANE_REPLICAS@@|${CONTROL_PLANE_REPLICAS}|g" \
    -e "s|@@COMPUTE_REPLICAS@@|${COMPUTE_REPLICAS}|g" \
    -e "s|@@CLUSTER_NETWORK_CIDR@@|${CLUSTER_NETWORK_CIDR}|g" \
    -e "s|@@CLUSTER_NETWORK_HOST_PREFIX@@|${CLUSTER_NETWORK_HOST_PREFIX}|g" \
    -e "s|@@SERVICE_NETWORK_CIDR@@|${SERVICE_NETWORK_CIDR}|g" \
    -e "s|@@NETWORK_TYPE@@|${NETWORK_TYPE}|g" \
    -e "s|@@INSTALL_PLATFORM@@|${INSTALL_PLATFORM}|g" \
    -e "s|@@PULL_SECRET@@|${pull_secret}|g" \
    -e "s|@@SSH_PUBKEY@@|${ssh_pubkey}|g" \
    -e "s|@@IMAGE_MIRROR_HOST@@|${IMAGE_MIRROR_HOST}|g" \
    -e "s|@@IMAGE_MIRROR_PATH@@|${IMAGE_MIRROR_PATH}|g" \
    -e "s|@@IMAGE_SOURCE_RELEASE@@|${IMAGE_SOURCE_RELEASE}|g" \
    -e "s|@@IMAGE_SOURCE_CONTENT@@|${IMAGE_SOURCE_CONTENT}|g" \
    "${INSTALL_CONFIG_TEMPLATE}" > "${tmp_render}"

  awk -v trust_bundle="${trust_bundle}" '
    {
      if ($0 == "@@ADDITIONAL_TRUST_BUNDLE@@") {
        print trust_bundle
      } else {
        print
      }
    }
  ' "${tmp_render}" > "${SOURCE_INSTALL_CONFIG_FILE}"

  cp -f "${SOURCE_INSTALL_CONFIG_FILE}" "${INSTALL_CONFIG_FILE}"
  rm -f "${tmp_render}"

  log "rendered ${SOURCE_INSTALL_CONFIG_FILE}"
  log "copied install-config to ${INSTALL_CONFIG_FILE}"
}

main "$@"
