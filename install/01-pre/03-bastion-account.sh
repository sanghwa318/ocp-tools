#!/bin/bash
set -euo pipefail

ROOT_PASSWORD='telco1234'
DISABLE_ROOT_SSH='yes'

CREATE_EXTRA_USER='yes'
EXTRA_USER_NAME='core'
EXTRA_USER_PASSWORD='telco1234'
EXTRA_USER_GROUPS='wheel'
EXTRA_USER_SUDO_NOPASSWD='yes'

ENABLE_OC_AUTO_LOGIN='yes'
OC_LOGIN_USER='admin'
OC_LOGIN_PASSWORD='telco1234'
OC_LOGIN_SERVER='https://api.lgu.okd:6443'
BASTION_HOST_PATTERN='bastion'

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

set_password() {
  local user="$1"
  local password="$2"

  echo "${password}" | passwd --stdin "${user}" >/dev/null
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

  if [[ "${EXTRA_USER_SUDO_NOPASSWD}" != "yes" ]]; then
    return 0
  fi

  echo "${user} ALL=(ALL) NOPASSWD: ALL" > "${sudoers_file}"
  chmod 0440 "${sudoers_file}"

  if ! visudo -cf "${sudoers_file}" >/dev/null 2>&1; then
    err "invalid sudoers file: ${sudoers_file}"
    exit 1
  fi

  log "sudoers configured for ${user}"
}

disable_root_ssh_login() {
  if [[ "${DISABLE_ROOT_SSH}" != "yes" ]]; then
    return 0
  fi

  if grep -qE '^[#[:space:]]*PermitRootLogin[[:space:]]+' /etc/ssh/sshd_config; then
    sed -i 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin no/' /etc/ssh/sshd_config
  else
    echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
  fi

  systemctl restart sshd
  log "root ssh login disabled"
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
      if [ -n "${OC_LOGIN_SERVER}" ]; then
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
  log "setting root password"
  set_password root "${ROOT_PASSWORD}"

  disable_root_ssh_login
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

main() {
  configure_root
  configure_extra_user
}

main "$@"

