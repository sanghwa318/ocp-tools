#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"

USER_NAME="${USER_NAME:-admin}"
USER_PASSWORD="${USER_PASSWORD:-}"
HTPASSWD_FILE="${HTPASSWD_FILE:-./htpasswd}"
SECRET_NAME="${SECRET_NAME:-htpasswd-secret}"
OAUTH_NAME="${OAUTH_NAME:-cluster}"
IDP_NAME="${IDP_NAME:-htpasswd}"

ensure_required_values() {
  [[ -n "${USER_NAME}" ]] || die "USER_NAME is required"
  [[ -n "${USER_PASSWORD}" ]] || die "USER_PASSWORD is required"
}

ensure_tools() {
  require_cmd oc
  require_cmd htpasswd
  require_oc_login
}

create_or_update_htpasswd_file() {
  log "creating or updating htpasswd file"
  htpasswd -bBc "${HTPASSWD_FILE}" "${USER_NAME}" "${USER_PASSWORD}"
}

apply_secret() {
  log "applying secret ${SECRET_NAME}"
  oc create secret generic "${SECRET_NAME}" \
    --from-file=htpasswd="${HTPASSWD_FILE}" \
    -n openshift-config \
    --dry-run=client -o yaml | oc apply -f -
}

apply_oauth_idp() {
  log "applying OAuth identity provider"

  cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: ${OAUTH_NAME}
spec:
  identityProviders:
  - name: ${IDP_NAME}
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: ${SECRET_NAME}
EOF
}

grant_cluster_admin() {
  log "granting cluster-admin to ${USER_NAME}"
  oc adm policy add-cluster-role-to-user cluster-admin "${USER_NAME}"
}

verify() {
  log "verifying secret ${SECRET_NAME}"
  oc get secret "${SECRET_NAME}" -n openshift-config >/dev/null

  log "verifying OAuth ${OAUTH_NAME}"
  oc get oauth "${OAUTH_NAME}" -o jsonpath='{.spec.identityProviders[*].name}{"\n"}' | grep -qw "${IDP_NAME}"

  log "verifying cluster-admin binding for ${USER_NAME}"
  oc adm policy who-can '*' '*' >/dev/null 2>&1 || true
}

main() {
  ensure_tools
  ensure_required_values
  create_or_update_htpasswd_file
  apply_secret
  apply_oauth_idp
  grant_cluster_admin
  verify

  log "done"
  echo "User: ${USER_NAME}"
}

main "$@"
