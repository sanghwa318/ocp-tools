#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
VARS_DIR="${SCRIPT_DIR}/00-vars"

# shellcheck disable=SC1091
source "${LIB_DIR}/common.sh"

load_env_file "${VARS_DIR}/cluster.env"
load_env_file "${VARS_DIR}/network.env"
load_env_file "${VARS_DIR}/registry.env"
load_env_file "${VARS_DIR}/bastion.env"
load_env_file "${VARS_DIR}/install-config.env"
load_env_file "${VARS_DIR}/post.env"

MODE="${1:-}"

ensure_install_workdir_is_clean() {
  if [[ -e "${INSTALL_WORKDIR}" ]]; then
    die "install workdir already exists: ${INSTALL_WORKDIR}"
  fi
}

run_pre() {
  print_section "RUN PRE"
  bash "${SCRIPT_DIR}/01-pre/00-command-extract.sh"
  bash "${SCRIPT_DIR}/01-pre/01-disable-selinux.sh"
  bash "${SCRIPT_DIR}/01-pre/02-bastion-account.sh"
  bash "${SCRIPT_DIR}/01-pre/03-bastion-chrony.sh"
  bash "${SCRIPT_DIR}/01-pre/04-make-certs.sh"
  bash "${SCRIPT_DIR}/01-pre/05-registry.sh"
  bash "${SCRIPT_DIR}/01-pre/06-hosts-render.sh"
  bash "${SCRIPT_DIR}/01-pre/07-dns-render.sh"
  bash "${SCRIPT_DIR}/01-pre/08-haproxy-render.sh"
  bash "${SCRIPT_DIR}/01-pre/09-tftp-install.sh"
  bash "${SCRIPT_DIR}/01-pre/10-dhcp-render.sh"
  bash "${SCRIPT_DIR}/01-pre/11-pxe-grub-render.sh"
  bash "${SCRIPT_DIR}/01-pre/12-keepalived-render.sh"
}

run_install() {
  print_section "RUN INSTALL"
  bash "${SCRIPT_DIR}/02-install/00-install-config-render.sh"
  bash "${SCRIPT_DIR}/02-install/01-manifests-generate.sh"
  bash "${SCRIPT_DIR}/02-install/01a-mc-init-render.sh"
  bash "${SCRIPT_DIR}/02-install/02-ignition-generate.sh"
  bash "${SCRIPT_DIR}/02-install/03-publish-artifacts.sh"
#  bash "${SCRIPT_DIR}/02-install/04-create-cluster.sh"
}

run_post() {
  print_section "RUN POST"
  bash "${SCRIPT_DIR}/03-post/00-openshift-admin-user.sh"
  bash "${SCRIPT_DIR}/03-post/01-ingress-master.sh"
  bash "${SCRIPT_DIR}/03-post/02-whereabouts-reconciler.sh"
  bash "${SCRIPT_DIR}/03-post/03-userWorkloadMonitoring.sh"
  bash "${SCRIPT_DIR}/03-post/04-routingViaHost.sh"
  bash "${SCRIPT_DIR}/03-post/05-enableCatalogSources.sh"
}

case "${MODE}" in
  pre) run_pre ;;
  install) run_install ;;
  post) run_post ;;
  *)
    die "usage: $0 [pre|install|post]"
    ;;
esac
