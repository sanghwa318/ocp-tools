SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${INSTALL_DIR}/00-inventory/hosts.txt"

BS=$(cat ${INVENTORY_FILE} |grep bootstrap |awk '{print$1}' )
ssh core@${BS} sudo mkdir /run/containers/62011
ssh core@${BS} sudo cp /root/.docker/config.json /run/containers/62011/auth.json
ssh core@${BS} sudo chmod a+r /run/containers/62011/auth.json
ssh core@${BS} sudo chmod a+rx /run/containers
