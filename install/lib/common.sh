#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

err() {
  echo "[ERROR] $*" >&2
}

die() {
  err "$*"
  exit 1
}

print_section() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "command not found: ${cmd}"
}

require_oc_login() {
  require_cmd oc
  oc whoami >/dev/null 2>&1 || die "oc is not logged in"
}

ensure_dir() {
  local dir="$1"
  mkdir -p "${dir}"
}

backup_file() {
  local file="$1"
  local suffix="${2:-$(date +%Y%m%d%H%M%S).bak}"

  [[ -f "${file}" ]] || return 0
  cp -a "${file}" "${file}.${suffix}"
  log "backup created: ${file}.${suffix}"
}

load_env_file() {
  local env_file="$1"
  [[ -f "${env_file}" ]] || die "env file not found: ${env_file}"

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

bool_normalize() {
  case "${1:-}" in
    true|false) echo "${1}" ;;
    yes) echo "true" ;;
    no) echo "false" ;;
    1) echo "true" ;;
    0) echo "false" ;;
    *) die "invalid boolean value: ${1:-}" ;;
  esac
}

resource_exists() {
  local kind="$1"
  local name="$2"
  local namespace="${3:-}"

  if [[ -n "${namespace}" ]]; then
    oc get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1
  else
    oc get "${kind}" "${name}" >/dev/null 2>&1
  fi
}

run_or_die() {
  "$@" || die "command failed: $*"
}

sshd_validate() {
  require_cmd sshd
  sshd -t
}

chrony_validate() {
  local conf_file="$1"
  require_cmd chronyd
  chronyd -p -f "${conf_file}" >/dev/null
}
