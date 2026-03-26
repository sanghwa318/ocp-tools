#!/usr/bin/env bash
set -euo pipefail

DATE=$(date +%Y%m%d)
BACKUPDIR=/root/growin/${DATE}
PARALLEL_NS=${PARALLEL_NS:-12}

mkdir -p "${BACKUPDIR}"

# dirs
POD=${BACKUPDIR}/pod
SVC=${BACKUPDIR}/service
STS=${BACKUPDIR}/statefulset
DEP=${BACKUPDIR}/deployment
DEPC=${BACKUPDIR}/deploymentconfig
DAE=${BACKUPDIR}/daemonset
PVC=${BACKUPDIR}/pvc
VM=${BACKUPDIR}/VM
NAD=${BACKUPDIR}/NAD
CSV=${BACKUPDIR}/CSV              # (옵션) ns별 저장 원하면 사용
CM=${BACKUPDIR}/CM

PV=${BACKUPDIR}/pv
NODE=${BACKUPDIR}/node
CO=${BACKUPDIR}/CO
MC=${BACKUPDIR}/MC
MCP=${BACKUPDIR}/MCP
SC=${BACKUPDIR}/SC
KC=${BACKUPDIR}/KC

CSV_DEDUP_DIR=${BACKUPDIR}/CSV_dedup
CSV_INDEX=${CSV_DEDUP_DIR}/csv_names.index
CSV_LOCK=${CSV_DEDUP_DIR}/csv_names.lock

mkdir -p "$POD" "$SVC" "$STS" "$DEP" "$DEPC" "$DAE" "$PVC" "$VM" "$NAD" "$CSV" "$CM" \
         "$PV" "$NODE" "$CO" "$MC" "$MCP" "$SC" "$KC" "$CSV_DEDUP_DIR"
touch "$CSV_INDEX"

LOG_ERR="${BACKUPDIR}/backup.err"
LOG_WARN="${BACKUPDIR}/backup.warn"
: > "$LOG_ERR"
: > "$LOG_WARN"

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "[FATAL] missing cmd: $1" | tee -a "$LOG_ERR"; exit 1; }; }
need_cmd oc
need_cmd jq
need_cmd flock

SCRIPT_PATH="$(readlink -f "$0")"

has_resource() {
  local r="$1"
  oc api-resources --no-headers -o name 2>>"$LOG_ERR" | grep -qxF "$r"
}

# ns당 1회 list 호출(JSON) -> items[]를 개별 json 파일로 저장
# output: <outdir>/<ns>_<name>.json
split_list_json_to_files() {
  local res="$1" ns="$2" outdir="$3"

  oc get "$res" -n "$ns" -o json 2>>"$LOG_ERR" \
  | jq -c '.items[]?' \
  | while read -r obj; do
      local name
      name=$(jq -r '.metadata.name' <<<"$obj")
      jq '.' <<<"$obj" > "${outdir}/${ns}_${name}.json"
    done
}

# CSV: name 기준 dedup (ns 무관 1회만 저장)
dedup_csv_ns() {
  local ns="$1"

  oc get csv -n "$ns" -o json 2>>"$LOG_ERR" \
  | jq -c '.items[]?' \
  | while read -r obj; do
      local name
      name=$(jq -r '.metadata.name' <<<"$obj")

      (
        flock -x 200
        if grep -qxF "$name" "$CSV_INDEX"; then
          exit 0
        fi
        echo "$name" >> "$CSV_INDEX"
        jq '.' <<<"$obj" > "${CSV_DEDUP_DIR}/${name}.json"
      ) 200>"$CSV_LOCK"
    done
}

backup_one_ns() {
  set -euo pipefail
  local ns="$1"

  split_list_json_to_files pod "$ns" "$POD" || true
  split_list_json_to_files svc "$ns" "$SVC" || true
  split_list_json_to_files sts "$ns" "$STS" || true
  split_list_json_to_files deployment "$ns" "$DEP" || true
  split_list_json_to_files daemonset "$ns" "$DAE" || true
  split_list_json_to_files network-attachment-definition "$ns" "$NAD" || true
  split_list_json_to_files cm "$ns" "$CM" || true

  # optional resources
  if has_resource deploymentconfigs; then
    split_list_json_to_files deploymentconfigs "$ns" "$DEPC" || true
  fi
  if has_resource vm; then
    split_list_json_to_files vm "$ns" "$VM" || true
  fi

  # pvc: 기존처럼 describe 유지(텍스트)
  oc get pvc -n "$ns" -o json 2>>"$LOG_ERR" \
  | jq -r '.items[]?.metadata.name' \
  | while read -r name; do
      oc describe pvc -n "$ns" "$name" > "${PVC}/${ns}_${name}" 2>>"$LOG_ERR" \
      || echo "[WARN] pvc describe failed: ${ns}/${name}" >> "$LOG_WARN"
    done

  # csv dedup
  if has_resource csv; then
    dedup_csv_ns "$ns" || true
  fi
}

if [[ "${1:-}" == "--ns" ]]; then
  backup_one_ns "${2:?ns required}"
  exit 0
fi

# Snapshot (wide)
oc get node -o wide > "${BACKUPDIR}/oc_get_node"
oc get po -A -o wide > "${BACKUPDIR}/oc_get_po_-A"
oc get all -A -o wide > "${BACKUPDIR}/oc_get_all_-A"
oc get svc -A -o wide > "${BACKUPDIR}/oc_get_svc_-A"
oc get pvc -A -o wide > "${BACKUPDIR}/oc_get_pvc_-A"
oc get pv -A -o wide  > "${BACKUPDIR}/oc_get_pv_-A"
oc get ing -A -o wide > "${BACKUPDIR}/oc_get_ing_-A"
oc get sts -A -o wide > "${BACKUPDIR}/oc_get_sts_-A"
oc get route -A -o wide > "${BACKUPDIR}/oc_get_route_-A"
oc get deployment -A -o wide > "${BACKUPDIR}/oc_get_deployment_-A"
oc get daemonset -A -o wide > "${BACKUPDIR}/oc_get_daemonset_-A"
oc get mc -A -o wide > "${BACKUPDIR}/oc_get_mc_-A"
oc get mcp -A -o wide > "${BACKUPDIR}/oc_get_mcp_-A"
oc get co -A -o wide > "${BACKUPDIR}/oc_get_co_-A"
oc get sc -o wide > "${BACKUPDIR}/oc_get_sc"
oc get kubeletconfig -o wide > "${BACKUPDIR}/oc_get_kc"
oc get network-attachment-definition -A -o wide > "${BACKUPDIR}/oc_get_nad_-A"
oc api-resources > "${BACKUPDIR}/oc_api-resources"
oc get csv -A > "${BACKUPDIR}/oc_get_csv_-A"
oc get cm -A > "${BACKUPDIR}/oc_get_cm_-A"

# cluster-scope objects (yaml 대신 json 저장)
oc get pv -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get pv "$n" -o json > "${PV}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get node -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get node "$n" -o json > "${NODE}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get co -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get co "$n" -o json > "${CO}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get mc -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get mc "$n" -o json > "${MC}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get mcp -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get mcp "$n" -o json > "${MCP}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get sc -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get sc "$n" -o json > "${SC}/${n}.json" 2>>"$LOG_ERR" || true; done
oc get kubeletconfig -o json | jq -r '.items[].metadata.name' | while read -r n; do oc get kubeletconfig "$n" -o json > "${KC}/${n}.json" 2>>"$LOG_ERR" || true; done

# ns parallel (no xargs re-exec)
running=0
while read -r ns; do
  # ns 하나 백업을 백그라운드로 실행
  (
    backup_one_ns "$ns"
  ) >>"$LOG_WARN" 2>>"$LOG_ERR" &

  running=$((running+1))

  # 동시성 제한
  if (( running >= PARALLEL_NS )); then
    # bash 4.3+ : wait -n 지원 (RHEL8/9는 OK)
    wait -n || true
    running=$((running-1))
  fi
done < <(oc get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# 남은 백그라운드 종료 대기
wait || true

echo "[DONE] backupdir=${BACKUPDIR}"
echo "[DONE] warn=${LOG_WARN} err=${LOG_ERR}"