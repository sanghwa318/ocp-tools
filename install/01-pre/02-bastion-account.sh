#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/bastion.env"
load_env_file "${INSTALL_DIR}/00-vars/cluster.env"

SSHD_INCLUDE_DIR="${SSHD_INCLUDE_DIR:-/etc/ssh/sshd_config.d}"
SSHD_GROWIN_CONF="${SSHD_GROWIN_CONF:-${SSHD_INCLUDE_DIR}/99-growin.conf}"

ensure_required_values() {
  [[ -n "${ROOT_PASSWORD}" ]] || die "ROOT_PASSWORD is required"
  if [[ "${CREATE_EXTRA_USER}" == "yes" ]]; then
    [[ -n "${EXTRA_USER_NAME}" ]] || die "EXTRA_USER_NAME is required"
    [[ -n "${EXTRA_USER_PASSWORD}" ]] || die "EXTRA_USER_PASSWORD is required"
  fi
}

set_password() {
  local user="$1"
  local password="$2"

  echo "${user}:${password}" | chpasswd
}

ensure_user_exists() {
  local user="$1"
  local groups="$2"

  if id "${user}" >/dev/null 2>&1; then
    log "user ${user} already exists"
    return 0
  fi

  if [[ -n "${groups}" ]]; then
    useradd -m -G "${groups}" "${user}"
  else
    useradd -m "${user}"
  fi

  log "user ${user} created"
}

ensure_sudoers_nopasswd() {
  local user="$1"
  local sudoers_file="/etc/sudoers.d/${user}"

  [[ "${EXTRA_USER_SUDO_NOPASSWD}" == "yes" ]] || return 0

  echo "${user} ALL=(ALL) NOPASSWD: ALL" > "${sudoers_file}"
  chmod 0440 "${sudoers_file}"

  require_cmd visudo
  visudo -cf "${sudoers_file}" >/dev/null 2>&1 || die "invalid sudoers file: ${sudoers_file}"

  log "sudoers configured for ${user}"
}

configure_root_ssh_policy() {
  ensure_dir "${SSHD_INCLUDE_DIR}"

  if [[ "${DISABLE_ROOT_SSH}" == "yes" ]]; then
    cat > "${SSHD_GROWIN_CONF}" <<EOF
PermitRootLogin no
EOF
  else
    cat > "${SSHD_GROWIN_CONF}" <<EOF
PermitRootLogin yes
EOF
  fi

  sshd_validate
  systemctl restart sshd
  log "sshd policy updated"
}

append_usr_local_bin_block() {
  local target_user="$1"
  local home_dir="$2"
  local bashrc="${home_dir}/.bashrc"

  [[ -d "${home_dir}" ]] || return 0
  touch "${bashrc}"

  if grep -q 'BEGIN_ADD_USR_LOCAL_BIN' "${bashrc}" 2>/dev/null; then
    log "${bashrc} already contains /usr/local/bin block"
    return 0
  fi

  cat <<'EOF' >> "${bashrc}"
# BEGIN_ADD_USR_LOCAL_BIN
case ":$PATH:" in
  *:/usr/local/bin:*)
    ;;
  *)
    export PATH="$PATH:/usr/local/bin"
    ;;
esac
# END_ADD_USR_LOCAL_BIN
EOF

  chown "${target_user}:${target_user}" "${bashrc}" 2>/dev/null || true
  log "/usr/local/bin block appended to ${bashrc}"
}

append_oc_login_block() {
  local target_user="$1"
  local home_dir="$2"
  local bashrc="${home_dir}/.bashrc"

  [[ "${ENABLE_OC_AUTO_LOGIN}" == "yes" ]] || return 0
  [[ -d "${home_dir}" ]] || return 0

  touch "${bashrc}"

  if grep -q 'BEGIN_OC_AUTO_LOGIN' "${bashrc}" 2>/dev/null; then
    log "${bashrc} already contains oc auto login block"
    return 0
  fi

  cat <<EOF >> "${bashrc}"
# BEGIN_OC_AUTO_LOGIN
case \$- in
  *i*) ;;
  *) return ;;
esac

if command -v oc >/dev/null 2>&1; then
  if hostname | grep -q '${BASTION_HOST_PATTERN}' ; then
    if ! oc whoami >/dev/null 2>&1; then
      if [ -n "${OC_LOGIN_SERVER}" ] && [ -n "${OC_LOGIN_USER}" ] && [ -n "${OC_LOGIN_PASSWORD}" ]; then
        oc login --server "${OC_LOGIN_SERVER}" --insecure-skip-tls-verify=true -u "${OC_LOGIN_USER}" -p '${OC_LOGIN_PASSWORD}' >/dev/null 2>&1
      fi
    fi
  fi
fi
# END_OC_AUTO_LOGIN
EOF

  chown "${target_user}:${target_user}" "${bashrc}" 2>/dev/null || true
  log "oc auto login block appended to ${bashrc}"
}

configure_root() {
  log "configuring root"
  set_password root "${ROOT_PASSWORD}"
  append_usr_local_bin_block root /root
  append_oc_login_block root /root
}

configure_extra_user() {
  [[ "${CREATE_EXTRA_USER}" == "yes" ]] || {
    log "extra user creation skipped"
    return 0
  }

  ensure_user_exists "${EXTRA_USER_NAME}" "${EXTRA_USER_GROUPS}"
  set_password "${EXTRA_USER_NAME}" "${EXTRA_USER_PASSWORD}"
  ensure_sudoers_nopasswd "${EXTRA_USER_NAME}"
  append_usr_local_bin_block "${EXTRA_USER_NAME}" "/home/${EXTRA_USER_NAME}"
  append_oc_login_block "${EXTRA_USER_NAME}" "/home/${EXTRA_USER_NAME}"
}

main() {
  require_root
  require_cmd systemctl
  require_cmd sshd
  require_cmd chpasswd

  ensure_required_values
  configure_root
  configure_extra_user
  configure_root_ssh_policy
}

main "$@"
