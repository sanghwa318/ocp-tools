#!/bin/bash
set -euo pipefail

CHRONY_CONF='/etc/chrony.conf'
CHRONY_SERVICE='chronyd'
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"

NTP_SERVERS=(
  "172.30.120.100 iburst"
)

ALLOW_NETWORKS=(
  "192.168.200.0/16"
)

LOCAL_STRATUM='10'
DRIFTFILE='/var/lib/chrony/drift'
KEYFILE='/etc/chrony.keys'
LOGDIR='/var/log/chrony'
LEAPSECTZ='right/UTC'
MAKESTEP='1.0 3'
RTCSYNC='yes'
SERVE_LOCAL_TIME='yes'
ENABLE_LOG_MEASUREMENTS='no'
ENABLE_LOG_STATISTICS='no'
ENABLE_LOG_TRACKING='no'

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "run as root"
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    err "command not found: ${cmd}"
    exit 1
  }
}

backup_file() {
  local file="$1"

  [[ -f "${file}" ]] || return 0

  cp -a "${file}" "${file}.${BACKUP_SUFFIX}.bak"
  log "backup created: ${file}.${BACKUP_SUFFIX}.bak"
}

write_chrony_conf() {
  {
    echo "# Managed by growin"
    echo

    for server in "${NTP_SERVERS[@]}"; do
      echo "server ${server}"
    done

    echo
    echo "# Record the rate at which the system clock gains/losses time."
    echo "driftfile ${DRIFTFILE}"
    echo
    echo "# Allow the system clock to be stepped in the first three updates"
    echo "# if its offset is larger than 1 second."
    echo "makestep ${MAKESTEP}"
    echo

    if [[ "${RTCSYNC}" == "yes" ]]; then
      echo "# Enable kernel synchronization of the real-time clock (RTC)."
      echo "rtcsync"
      echo
    fi

    if [[ "${#ALLOW_NETWORKS[@]}" -gt 0 ]]; then
      echo "# Allow NTP client access from local network."
      for net in "${ALLOW_NETWORKS[@]}"; do
        echo "allow ${net}"
      done
      echo
    fi

    if [[ "${SERVE_LOCAL_TIME}" == "yes" ]]; then
      echo "# Serve time even if not synchronized to a time source."
      echo "local stratum ${LOCAL_STRATUM}"
      echo
    fi

    echo "# Specify file containing keys for NTP authentication."
    echo "keyfile ${KEYFILE}"
    echo
    echo "# Get TAI-UTC offset and leap seconds from the system tz database."
    echo "leapsectz ${LEAPSECTZ}"
    echo
    echo "# Specify directory for log files."
    echo "logdir ${LOGDIR}"
    echo

    LOG_ITEMS=()
    [[ "${ENABLE_LOG_MEASUREMENTS}" == "yes" ]] && LOG_ITEMS+=("measurements")
    [[ "${ENABLE_LOG_STATISTICS}" == "yes" ]] && LOG_ITEMS+=("statistics")
    [[ "${ENABLE_LOG_TRACKING}" == "yes" ]] && LOG_ITEMS+=("tracking")

    if [[ "${#LOG_ITEMS[@]}" -gt 0 ]]; then
      echo "# Select which information is logged."
      echo "log ${LOG_ITEMS[*]}"
      echo
    fi
  } > "${CHRONY_CONF}"
}

validate_config() {
  chronyd -p -f "${CHRONY_CONF}" >/dev/null
  log "chrony config validation passed"
}

restart_service() {
  systemctl enable --now "${CHRONY_SERVICE}"
  systemctl restart "${CHRONY_SERVICE}"
  systemctl --no-pager --full status "${CHRONY_SERVICE}" | head -n 20 || true
}

show_result() {
  echo
  chronyc sources -v || true
  echo
  chronyc tracking || true
}

main() {
  require_root
  require_cmd chronyd
  require_cmd chronyc
  require_cmd systemctl

  if [[ "${#NTP_SERVERS[@]}" -eq 0 ]]; then
    err "at least one NTP server is required"
    exit 1
  fi

  mkdir -p "${LOGDIR}"
  backup_file "${CHRONY_CONF}"
  write_chrony_conf
  validate_config
  restart_service
  show_result
}

main "$@"
