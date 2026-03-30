#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/network.env"

CHRONY_CONF="${CHRONY_CONF:-/etc/chrony.conf}"
CHRONY_SERVICE="${CHRONY_SERVICE:-chronyd}"
LOCAL_STRATUM="${LOCAL_STRATUM:-10}"
DRIFTFILE="${DRIFTFILE:-/var/lib/chrony/drift}"
KEYFILE="${KEYFILE:-/etc/chrony.keys}"
LOGDIR="${LOGDIR:-/var/log/chrony}"
LEAPSECTZ="${LEAPSECTZ:-right/UTC}"
MAKESTEP="${MAKESTEP:-1.0 3}"
RTCSYNC="${RTCSYNC:-yes}"
SERVE_LOCAL_TIME="${SERVE_LOCAL_TIME:-yes}"
ENABLE_LOG_MEASUREMENTS="${ENABLE_LOG_MEASUREMENTS:-no}"
ENABLE_LOG_STATISTICS="${ENABLE_LOG_STATISTICS:-no}"
ENABLE_LOG_TRACKING="${ENABLE_LOG_TRACKING:-no}"

write_chrony_conf() {
  {
    echo "# Managed by growin"
    echo

    echo "server ${NTP_SERVERS}"
    echo
    echo "driftfile ${DRIFTFILE}"
    echo "makestep ${MAKESTEP}"
    echo

    if [[ "${RTCSYNC}" == "yes" ]]; then
      echo "rtcsync"
      echo
    fi

    if [[ -n "${ALLOW_NETWORKS}" ]]; then
      echo "allow ${ALLOW_NETWORKS}"
      echo
    fi

    if [[ "${SERVE_LOCAL_TIME}" == "yes" ]]; then
      echo "local stratum ${LOCAL_STRATUM}"
      echo
    fi

    echo "keyfile ${KEYFILE}"
    echo "leapsectz ${LEAPSECTZ}"
    echo "logdir ${LOGDIR}"
    echo

    local log_items=()
    [[ "${ENABLE_LOG_MEASUREMENTS}" == "yes" ]] && log_items+=("measurements")
    [[ "${ENABLE_LOG_STATISTICS}" == "yes" ]] && log_items+=("statistics")
    [[ "${ENABLE_LOG_TRACKING}" == "yes" ]] && log_items+=("tracking")

    if [[ "${#log_items[@]}" -gt 0 ]]; then
      echo "log ${log_items[*]}"
    fi
  } > "${CHRONY_CONF}"
}

main() {
  require_root
  require_cmd chronyd
  require_cmd chronyc
  require_cmd systemctl

  [[ -n "${NTP_SERVERS}" ]] || die "NTP_SERVERS is required"

  ensure_dir "${LOGDIR}"
  backup_file "${CHRONY_CONF}"
  write_chrony_conf
  chrony_validate "${CHRONY_CONF}"

  systemctl enable --now "${CHRONY_SERVICE}"
  systemctl restart "${CHRONY_SERVICE}"
  systemctl --no-pager --full status "${CHRONY_SERVICE}" | head -n 20 || true

  echo
  chronyc sources -v || true
  echo
  chronyc tracking || true
}

main "$@"
