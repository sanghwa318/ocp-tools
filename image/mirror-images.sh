#!/usr/bin/env bash
set -euo pipefail

SRC_FILE="${1:-images.txt}"
DEST_REG="${2:-bastion.ocp.lsh:5000}"
JOBS="${3:-6}"
RETRY="${4:-2}"
LOGDIR="${5:-./mirror-logs}"

###############################################################################
# Default credentials
# Fill these in.
###############################################################################
DEFAULT_USER="joo@growin.co.kr"
DEFAULT_PASSWORD="d!JVFvm7!Cm78iz"

# Per-registry credentials
# Leave as-is to inherit DEFAULT_USER / DEFAULT_PASSWORD.
DOCKER_IO_USER="${DOCKER_IO_USER:-$DEFAULT_USER}"
DOCKER_IO_PASSWORD="${DOCKER_IO_PASSWORD:-$DEFAULT_PASSWORD}"

QUAY_IO_USER="${QUAY_IO_USER:-$DEFAULT_USER}"
QUAY_IO_PASSWORD="${QUAY_IO_PASSWORD:-$DEFAULT_PASSWORD}"

REGISTRY_REDHAT_IO_USER="${REGISTRY_REDHAT_IO_USER:-$DEFAULT_USER}"
REGISTRY_REDHAT_IO_PASSWORD="${REGISTRY_REDHAT_IO_PASSWORD:-$DEFAULT_PASSWORD}"

REGISTRY_CONNECT_REDHAT_COM_USER="${REGISTRY_CONNECT_REDHAT_COM_USER:-$DEFAULT_USER}"
REGISTRY_CONNECT_REDHAT_COM_PASSWORD="${REGISTRY_CONNECT_REDHAT_COM_PASSWORD:-$DEFAULT_PASSWORD}"

DEST_REG_USER="${DEST_REG_USER:-$DEFAULT_USER}"
DEST_REG_PASSWORD="${DEST_REG_PASSWORD:-$DEFAULT_PASSWORD}"
###############################################################################

mkdir -p "$LOGDIR"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

LIST="$WORKDIR/list.txt"
OK="$LOGDIR/success.txt"
FAIL="$LOGDIR/fail.txt"

: > "$OK"
: > "$FAIL"

echo "[INFO] extracting images..."

sed -E 's/^[[:space:]-]*image:[[:space:]]*//; s/^"//; s/"$//' "$SRC_FILE" \
| sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
| grep -E '^[[:alnum:].-]+(:[0-9]+)?/[[:graph:]]+(@sha256:[a-f0-9]{64}|:[^[:space:]]+)$' \
| sort -u > "$LIST"

TOTAL=$(wc -l < "$LIST" | tr -d ' ')
echo "[INFO] total unique images: $TOTAL"

need_registry() {
  local reg="$1"
  grep -qE "^${reg}(/|:)" "$LIST"
}

podman_login_if_needed() {
  local reg="$1"
  local user="$2"
  local pass="$3"

  if ! need_registry "$reg"; then
    return 0
  fi

  if [[ -z "$user" || -z "$pass" ]]; then
    echo "[WARN] skip login for $reg (empty credentials)"
    return 0
  fi

  echo "[INFO] podman login: $reg"
  printf '%s' "$pass" | podman login "$reg" --username "$user" --password-stdin
}

echo "[INFO] login to required registries..."

podman_login_if_needed "docker.io" "$DOCKER_IO_USER" "$DOCKER_IO_PASSWORD"
podman_login_if_needed "quay.io" "$QUAY_IO_USER" "$QUAY_IO_PASSWORD"
podman_login_if_needed "registry.redhat.io" "$REGISTRY_REDHAT_IO_USER" "$REGISTRY_REDHAT_IO_PASSWORD"
podman_login_if_needed "registry.connect.redhat.com" "$REGISTRY_CONNECT_REDHAT_COM_USER" "$REGISTRY_CONNECT_REDHAT_COM_PASSWORD"

if [[ -n "$DEST_REG_USER" && -n "$DEST_REG_PASSWORD" ]]; then
  echo "[INFO] podman login: $DEST_REG"
  printf '%s' "$DEST_REG_PASSWORD" | podman login "$DEST_REG" --username "$DEST_REG_USER" --password-stdin
else
  echo "[WARN] skip login for destination registry $DEST_REG (empty credentials)"
fi

copy_one() {
  local img="$1"
  local dst="${DEST_REG}/${img}"
  local name log
  name=$(echo "$img" | sed 's#[/:@]#_#g')
  log="$LOGDIR/${name}.log"

  if skopeo inspect --tls-verify=false "docker://${dst}" >/dev/null 2>&1; then
    echo "[SKIP] $img (already exists)"
    echo "$img" >> "$OK"
    return 0
  fi

  for ((i=1; i<=RETRY; i++)); do
    echo "[TRY $i/$RETRY] $img"

    if skopeo copy --all \
      --src-tls-verify=false \
      --dest-tls-verify=false \
      "docker://${img}" \
      "docker://${dst}" \
      >"$log" 2>&1
    then
      echo "[OK] $img"
      echo "$img" >> "$OK"
      return 0
    fi

    echo "[WARN] retry failed ($i/$RETRY): $img"
    sleep 2
  done

  echo "[FAIL] $img"
  echo "$img" >> "$FAIL"
  return 1
}

export DEST_REG LOGDIR OK FAIL RETRY
export -f copy_one

echo "[INFO] start parallel copy..."

xargs -r -P "$JOBS" -I{} bash -c 'copy_one "$@"' _ {} < "$LIST" || true

echo
echo "========== RESULT =========="
echo "TOTAL   : $TOTAL"
echo "SUCCESS : $(wc -l < "$OK" | tr -d ' ')"
echo "FAILED  : $(wc -l < "$FAIL" | tr -d ' ')"
echo "LOGDIR  : $LOGDIR"

if [ -s "$FAIL" ]; then
  echo
  echo "[FAILED LIST]"
  cat "$FAIL"
fi
