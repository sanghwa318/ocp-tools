# 10-enable-catalog-sources.sh
#!/bin/bash
set -euo pipefail

DISABLE_ALL_DEFAULT_SOURCES="${DISABLE_ALL_DEFAULT_SOURCES:-true}"
ENABLE_REDHAT_OPERATORS="${ENABLE_REDHAT_OPERATORS:-true}"
ENABLE_COMMUNITY_OPERATORS="${ENABLE_COMMUNITY_OPERATORS:-true}"
ENABLE_CERTIFIED_OPERATORS="${ENABLE_CERTIFIED_OPERATORS:-false}"
ENABLE_MARKETPLACE_OPERATORS="${ENABLE_MARKETPLACE_OPERATORS:-false}"

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "command not found: $1"; exit 1; }
}

check_oc() {
  oc whoami >/dev/null 2>&1 || { err "oc is not logged in"; exit 1; }
}

bool_to_disabled() {
  case "$1" in
    true) echo "false" ;;
    false) echo "true" ;;
    *) err "invalid boolean: $1"; exit 1 ;;
  esac
}

main() {
  require_cmd oc
  check_oc

  local redhat_disabled
  local community_disabled
  local certified_disabled
  local marketplace_disabled

  redhat_disabled="$(bool_to_disabled "${ENABLE_REDHAT_OPERATORS}")"
  community_disabled="$(bool_to_disabled "${ENABLE_COMMUNITY_OPERATORS}")"
  certified_disabled="$(bool_to_disabled "${ENABLE_CERTIFIED_OPERATORS}")"
  marketplace_disabled="$(bool_to_disabled "${ENABLE_MARKETPLACE_OPERATORS}")"

  log "patching operatorhubs.config.openshift.io/cluster"
  oc patch operatorhubs.config.openshift.io cluster \
    --type=merge \
    -p "{
      \"spec\": {
        \"disableAllDefaultSources\": ${DISABLE_ALL_DEFAULT_SOURCES},
        \"sources\": [
          {\"name\": \"redhat-operators\", \"disabled\": ${redhat_disabled}},
          {\"name\": \"community-operators\", \"disabled\": ${community_disabled}},
          {\"name\": \"certified-operators\", \"disabled\": ${certified_disabled}},
          {\"name\": \"redhat-marketplace\", \"disabled\": ${marketplace_disabled}}
        ]
      }
    }"

  log "verifying operatorhub sources"
  oc get operatorhubs.config.openshift.io cluster \
    -o jsonpath='{.spec.disableAllDefaultSources}{"\n"}{range .spec.sources[*]}{.name}{" | disabled="}{.disabled}{"\n"}{end}'
}

main "$@"
