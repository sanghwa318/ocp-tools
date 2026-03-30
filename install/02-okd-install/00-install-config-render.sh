#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${INSTALL_DIR}/templates"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

INSTALL_CONFIG_TEMPLATE="${TEMPLATE_DIR}/install-config.yaml.tmpl"

indent_file_two_spaces() {
  sed 's/^/  /' "$1"
}

main() {
  require_root
  require_cmd sed
  require_cmd awk

  [[ -f "${INSTALL_CONFIG_TEMPLATE}" ]] || die "template not found: ${INSTALL_CONFIG_TEMPLATE}"
  [[ -f "${PULL_SECRET_FILE}" ]] || die "pull secret file not found: ${PULL_SECRET_FILE}"
  [[ -f "${SSH_PUBKEY_FILE}" ]] || die "ssh pubkey file not found: ${SSH_PUBKEY_FILE}"
  [[ -f "${ADDITIONAL_TRUST_BUNDLE_FILE}" ]] || die "additional trust bundle file not found: ${ADDITIONAL_TRUST_BUNDLE_FILE}"

  ensure_dir "${INSTALL_WORKDIR}"

  local pull_secret
  local ssh_pubkey
  local trust_bundle
  local tmp_render

  pull_secret="$(tr -d '\n' < "${PULL_SECRET_FILE}" | sed 's/[&/\]/\\&/g')"
  ssh_pubkey="$(tr -d '\n' < "${SSH_PUBKEY_FILE}" | sed 's/[&/\]/\\&/g')"
  trust_bundle="$(indent_file_two_spaces "${ADDITIONAL_TRUST_BUNDLE_FILE}")"

  backup_file "${INSTALL_CONFIG_FILE}"

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
  ' "${tmp_render}" > "${INSTALL_CONFIG_FILE}"

  rm -f "${tmp_render}"

  log "rendered ${INSTALL_CONFIG_FILE}"
}

main "$@"
