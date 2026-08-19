#!/usr/bin/env bash
# learn — 지적을 쌓고, 반복되면 규칙 승격을 제안한다. docs/DESIGN.md 9장.
#
# 이 도구가 존재하는 이유가 여기다. 매번 같은 지적을 받는다면 루프가 도는 게
# 아니라 제자리걸음이다. findings.md 는 회고용이 아니라 **계기판**이다 —
# 커밋당 신규 지적 수가 줄어드는가가 이 도구가 작동하는지 아는 유일한 지표다.
#
# 왜 스크립트인가:
#   append 를 모델이 손으로 하면 형식이 흔들리고, 형식이 흔들리면 카운트가
#   깨진다. 카운트가 깨지면 승격 제안이 안 나오고, 그러면 루프가 닫히지 않는다.
#
# 왜 카테고리를 고정하는가:
#   "같은 종류의 지적 3회"를 자연어로 판단하면 그때그때 달라진다.
#   **필드 일치로 만들면 결정적으로 셀 수 있다.**
#
# 사용:
#   findings.sh add <카테고리> <요약> [파일] [처리]
#   findings.sh count            승격 후보(3회 이상)만 출력
#   findings.sh recent [N]       최근 N줄
#   findings.sh categories       허용 카테고리 목록
#
# 종료 코드는 언제나 0 — 기록이 실패해도 개발을 막지 않는다.
#
# set -e 를 쓰지 않는다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

# 카테고리는 리뷰 도구의 기준과 같은 축을 쓴다. 새로 정의하지 않는다 —
# frontend-fundamentals 의 4원칙 + verify 가 결정적으로 재는 것들.
CATEGORIES='cohesion coupling predictability readability duplication deadcode a11y naming other'

PROMOTE_AT=3

root=$(fh_root "")
FILE=$root/.fe-harness/findings.md

_usage() {
  printf '사용: findings.sh add <카테고리> <요약> [파일] [처리]\n'
  printf '      findings.sh count | recent [N] | categories\n'
  printf '카테고리: %s\n' "$CATEGORIES"
}

_valid_category() {
  local c
  for c in $CATEGORIES; do [ "$1" = "$c" ] && return 0; done
  return 1
}

_ensure_file() {
  mkdir -p "$(dirname "$FILE")" 2>/dev/null || return 1
  [ -f "$FILE" ] && return 0
  {
    printf '# findings — 루프가 도는 증거\n\n'
    printf '`/lap` 이 한 줄씩 덧붙인다. 손으로 고쳐도 되지만 탭 구분 6칸을 지킬 것.\n\n'
    printf '```\n날짜\t커밋\t출처\t카테고리\t요약\t파일\t처리\n```\n\n'
  } > "$FILE" 2>/dev/null
}

# 같은 카테고리가 PROMOTE_AT 회 이상이면 승격 후보다.
# 아직 승격 제안을 안 한 것만 센다 — 한 번 제안하고 사용자가 미뤘으면
# 매번 다시 묻지 않는다. 성가시면 끄게 된다.
_count() {
  [ -f "$FILE" ] || return 0
  awk -F'\t' -v n="$PROMOTE_AT" '
    /^[0-9]{4}-[0-9]{2}-[0-9]{2}\t/ {
      if ($7 !~ /^승격/) { c[$4]++; last[$4] = $5 }
    }
    END {
      for (k in c) if (c[k] >= n)
        printf "%s\t%d\t%s\n", k, c[k], last[k]
    }
  ' "$FILE" 2>/dev/null | sort -t"$(printf '\t')" -k2 -rn
}

cmd=${1:-}
case $cmd in
  add)
    category=${2:-}
    summary=${3:-}
    file=${4:--}
    action=${5:--}
    [ -n "$category" ] && [ -n "$summary" ] || { _usage; exit 0; }
    if ! _valid_category "$category"; then
      printf '알 수 없는 카테고리: %s\n허용: %s\n' "$category" "$CATEGORIES"
      exit 0
    fi
    _ensure_file || exit 0

    # 날짜는 시스템에서, 커밋은 git 에서. 둘 다 실패해도 기록은 남긴다.
    date_s=$(date +%Y-%m-%d 2>/dev/null || printf '?')
    sha=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || printf '-')

    # 탭과 개행이 섞이면 형식이 깨진다. 공백으로 눕힌다.
    summary=$(printf '%s' "$summary" | tr '\t\n' '  ')
    file=$(printf '%s' "$file" | tr '\t\n' '  ')
    action=$(printf '%s' "$action" | tr '\t\n' '  ')

    printf '%s\t%s\treview\t%s\t%s\t%s\t%s\n' \
      "$date_s" "$sha" "$category" "$summary" "$file" "$action" >> "$FILE"
    ;;

  count)
    out=$(_count)
    [ -n "$out" ] || exit 0
    printf '규칙으로 승격할 후보 (같은 카테고리 %s회 이상):\n' "$PROMOTE_AT"
    printf '%s\n' "$out" | while IFS=$(printf '\t') read -r cat n last; do
      printf '  %s — %s회. 최근: %s\n' "$cat" "$n" "$last"
    done
    printf '\n승격 경로는 지적의 성격이 정한다:\n'
    printf '  기계적으로 판정 가능  → hookify 규칙 (block / warn)\n'
    printf '  판단이 필요한 지침    → CLAUDE.md\n'
    printf '  이 저장소만의 맥락    → .fe-harness.json 의 guidance\n'
    ;;

  recent)
    [ -f "$FILE" ] || exit 0
    grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}	' "$FILE" 2>/dev/null | tail -n "${2:-10}"
    ;;

  categories) printf '%s\n' "$CATEGORIES" ;;
  *) _usage ;;
esac

exit 0
