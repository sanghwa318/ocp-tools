#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"


# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

mkdir /$(echo ${BASE_DOMAIN} | cut -d '.' -f1)
cp -r ${INSTALL_WORKDIR}/auth /$(echo ${BASE_DOMAIN} | cut -d '.' -f1)/auth
