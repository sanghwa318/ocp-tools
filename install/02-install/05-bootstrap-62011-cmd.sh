#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"


# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/install-config.env"

if OFFLINE=="true"; then
cat <<EOF > ${INSTALL_DIR}/02-install/bootstrap-62011.sh
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="\$(cd "\${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="\${INSTALL_DIR}/00-inventory/hosts.txt"

BS=\$(cat \${INVENTORY_FILE} |grep bootstrap |awk '{print\$1}' )
ssh core@\${BS} sudo mkdir /run/containers/62011
ssh core@\${BS} sudo cp /root/.docker/config.json /run/containers/62011/auth.json
ssh core@\${BS} sudo chmod a+r /run/containers/62011/auth.json
ssh core@\${BS} sudo chmod a+rx /run/containers
EOF
echo
echo "OFFLINE == true / run script ${INSTALL_DIR}/02-install/bootstrap-62011.sh"
echo
fi
