#!/usr/bin/env bash
# ocp-tools 설치 스크립트가 생성한 .bak 백업 파일 정리
# 사용법:
#   bash cleanup-bak.sh            # dry-run (삭제 목록만 출력)
#   bash cleanup-bak.sh --delete   # 실제 삭제
#   bash cleanup-bak.sh --delete --keep 3  # 각 원본 파일별 최신 3개 유지

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/root/ocp-tools/install}"
DRY_RUN=true
KEEP=0  # 0 = 전부 삭제, N = 최신 N개 유지

# 인수 파싱
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete) DRY_RUN=false ;;
    --keep)   KEEP="${2:-0}"; shift ;;
    --dir)    INSTALL_DIR="${2:-${INSTALL_DIR}}"; shift ;;
    -h|--help)
      echo "사용법: $0 [--delete] [--keep N] [--dir PATH]"
      echo "  --delete     실제 삭제 실행 (없으면 dry-run)"
      echo "  --keep N     원본 파일별 최신 N개 백업 유지 (기본: 0=전부 삭제)"
      echo "  --dir PATH   탐색 기준 디렉토리 (기본: ${INSTALL_DIR})"
      exit 0
      ;;
    *) echo "[ERROR] 알 수 없는 옵션: $1"; exit 1 ;;
  esac
  shift
done

echo "============================================================"
echo " OCP Forge — 백업 파일 정리"
echo "============================================================"
echo " 대상 디렉토리: ${INSTALL_DIR}"
echo " 모드:          $(${DRY_RUN} && echo 'DRY-RUN (--delete 없으면 삭제 안 함)' || echo '실제 삭제')"
echo " 유지 개수:     ${KEEP} 개 (0=전부 삭제)"
echo ""

# .숫자14자리.bak 패턴 파일 탐색
# 예: dhcpd.conf.20260427105242.bak
mapfile -t bak_files < <(
  find "${INSTALL_DIR}" -type f     -regextype posix-extended     -regex '.*\.[0-9]{14}\.bak$'   | sort
)

if [[ ${#bak_files[@]} -eq 0 ]]; then
  echo " 정리할 백업 파일이 없습니다."
  exit 0
fi

total_size=0
delete_count=0
keep_count=0

# 원본 파일별로 그룹핑 후 처리
declare -A groups

for f in "${bak_files[@]}"; do
  # 원본 파일 경로 추출: 파일명에서 .숫자14.bak 제거
  orig="${f%.*.*}"  # 마지막 .bak 제거 후 .타임스탬프 제거
  groups["${orig}"]+="${f}"$'\n'
done

for orig in $(echo "${!groups[@]}" | tr ' ' '\n' | sort); do
  # 해당 원본의 백업 파일들 (시간 역순 = 최신순)
  mapfile -t orig_baks < <(echo -e "${groups[$orig]}" | grep -v '^$' | sort -r)
  total=${#orig_baks[@]}

  echo "  [${orig##*/}] 백업 ${total}개"

  idx=0
  for bak in "${orig_baks[@]}"; do
    idx=$((idx + 1))
    size=$(stat -c%s "${bak}" 2>/dev/null || echo 0)
    ts=$(basename "${bak}" | grep -oP '[0-9]{14}')
    ts_fmt="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}"

    if [[ ${KEEP} -gt 0 && ${idx} -le ${KEEP} ]]; then
      echo "    KEEP   ${ts_fmt}  $(basename "${bak}")"
      keep_count=$((keep_count + 1))
    else
      total_size=$((total_size + size))
      delete_count=$((delete_count + 1))
      if ${DRY_RUN}; then
        echo "    DELETE ${ts_fmt}  $(basename "${bak}")"
      else
        rm -f "${bak}"
        echo "    DELETE ${ts_fmt}  $(basename "${bak}")  [삭제됨]"
      fi
    fi
  done
done

echo ""
echo "============================================================"
if ${DRY_RUN}; then
  echo " [DRY-RUN] 삭제 예정: ${delete_count}개 / 유지: ${keep_count}개"
  printf " 회수 예정 용량: %s\n" "$(numfmt --to=iec ${total_size} 2>/dev/null || echo "${total_size} bytes")"
  echo ""
  echo " 실제 삭제하려면: bash $0 --delete"
  [[ ${KEEP} -gt 0 ]] || echo " 최신 N개 유지하려면: bash $0 --delete --keep N"
else
  echo " 삭제 완료: ${delete_count}개 / 유지: ${keep_count}개"
  printf " 회수된 용량: %s\n" "$(numfmt --to=iec ${total_size} 2>/dev/null || echo "${total_size} bytes")"
fi
echo "============================================================"
