#!/usr/bin/env bash
# 분량 신호. PostToolUse(Write|Edit) — 넘으면 경고한다. 차단하지 않는다.
#
# 왜 차단이 아닌가 (v2 결정):
#   파일 길이는 "셀 수 있지만 판단이 필요한" 칸이다. 정당하게 긴 파일이 실재한다 —
#   데이터 테이블, API 응답 타입 정의, SVG 컴포넌트, 스키마. 실측 4.5% 가
#   걸리는데 Claude Code 로 하루 10~20개 파일을 만들면 주 3~6회다.
#   "정당하게 어겨야 하는 경우가 주 1회 이상이면 경고로 간다"는 자체 기준에 걸린다.
#
#   그리고 이 게이트를 정당화하던 명제("새 파일은 싸게, 기존 파일은 비싸게")는
#   v2 에서 폐기됐다. 근거가 철회된 장치를 "작동하니까" 남기지 않는다.
#
# 왜 그래도 임계값이 비대칭인가:
#   Write 는 파일 전문, Edit 는 이번에 붙이는 조각이라 재는 대상이 다르다.
#   같은 숫자를 쓸 수 없다.
#
# 판정 단위 (3장, 2026-08-18 실측 확인):
#   Write 의 content    = 파일 전문. 바이트 단위로 실제 파일과 일치함을 확인
#   Edit  의 new_string = 교체 조각. 파일 전문이 아니다
#   그래서 Edit 은 "이번 턴에 얼마나 붙이는가"를 재는 것이지
#   파일이 얼마나 큰가를 재는 게 아니다.
#
# PostToolUse 의 exit 2 는 차단이 아니라 stderr 를 Claude 에게 보여주는 것이다.
# 이미 써진 뒤이므로 문구는 "돌아가서 쪼개라"여야 한다. 다만 **방금 쓴 직후라
# 내용이 컨텍스트에 그대로 있어** 커밋 시점보다 쪼개는 비용이 훨씬 싸다.
#
# 끄는 방법은 stderr 에 쓰지 않는다 — 그건 사람에게 하는 말이고, 모델에게
# 알려주면 게이트를 끄는 쪽으로 갈 수 있다. README 에만 적는다.
#
# set -e 를 쓰지 않는다.
# macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

# jq 가 없으면 전체 no-op. 확신 없이 막는 것보다 안 막는 게 낫다.
command -v jq >/dev/null 2>&1 || exit 0

_field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

tool=$(_field '.tool_name')
file=$(_field '.tool_input.file_path')
root=$(fh_root "$(_field '.cwd')")

fh_disabled "$root" signals && exit 0

# 관찰 모드 — 기본 꺼짐. payload 를 저장소 밖에 떠서 디버깅에 쓴다 (8장).
if [ "$(fh_cfg "$root" '.observe')" = "true" ]; then
  observe_dir=${FE_HARNESS_OBSERVE_DIR:-${TMPDIR:-/tmp}/fe-harness-observe}
  if mkdir -p "$observe_dir" 2>/dev/null; then
    printf '%s' "$payload" > "$observe_dir/payload-$(date +%Y%m%d-%H%M%S)-$$.json"
  fi
fi

[ -n "$file" ] || exit 0
fh_ext_allowed "$root" "$file" || exit 0
fh_excluded "$root" "$file" && exit 0

case $tool in
  Write)
    body=$(_field '.tool_input.content')
    limit=$(fh_cfg_num "$root" '.signals.maxNewFileLines' 250)
    ;;
  Edit)
    body=$(_field '.tool_input.new_string')
    limit=$(fh_cfg_num "$root" '.signals.maxEditLines' 80)
    ;;
  *)
    exit 0
    ;;
esac

# 명령 치환이 끝의 개행을 지우므로 줄 수는 정확하고 바이트 수는 근사값이다.
lines=$(printf '%s' "$body" | awk 'END { print NR }')
[ "$lines" -gt "$limit" ] || exit 0

guidance=$(fh_cfg "$root" '.guidance')

{
  if [ "$tool" = Write ]; then
    printf 'fe-harness 신호: %s 를 %s줄로 썼습니다. 권장은 %s줄입니다.\n\n' \
      "${file##*/}" "$lines" "$limit"
    printf '지금이 쪼개기 가장 쌉니다 — 방금 쓴 내용이라 구조가 아직 머리에 있습니다.\n'
    printf '  1. 이 파일에서 독립적으로 재사용될 단위를 고른다\n'
    printf '  2. 그 단위를 각각 별도 파일로 Write 한다\n'
    printf '  3. 원래 파일에는 조립과 배치만 남긴다\n\n'
    printf '데이터 테이블 · 타입 정의 · SVG 처럼 정당하게 긴 파일이면 그냥 두세요.\n'
    printf '길이 자체가 문제가 아니라 한 파일이 여러 역할을 지는 것이 문제입니다.\n'
  else
    printf 'fe-harness 신호: %s 에 %s줄을 한 번에 붙였습니다. 권장은 %s줄입니다.\n\n' \
      "${file##*/}" "$lines" "$limit"
    printf '붙인 덩어리가 독립적인 단위라면 지금 빼내는 게 가장 쌉니다:\n'
    printf '  1. 추가하려는 내용이 독립적인 단위인지 본다\n'
    printf '  2. 맞으면 새 파일로 Write 하고 여기서는 import 만 한다\n'
    printf '  3. 아니면 의미 단위로 쪼개서 여러 번 Edit 한다\n\n'
    printf '새 파일을 만드는 쪽이 기존 파일을 불리는 쪽보다 쌉니다.\n'
  fi

  [ -n "$guidance" ] && printf '\n%s\n' "$guidance"
} >&2

# PostToolUse 의 exit 2 는 차단이 아니라 stderr 전달이다.
exit 2
