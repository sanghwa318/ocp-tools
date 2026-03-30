#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${INSTALL_DIR}/lib/common.sh"
load_env_file "${INSTALL_DIR}/00-vars/post.env"

bool_to_disabled() {
  case "$1" in
    true) echo "false" ;;
    false) echo "true" ;;
    *) die "invalid boolean: $1" ;;
  esac
}

main() {
  require_oc_login

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
