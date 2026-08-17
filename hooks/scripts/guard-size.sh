#!/usr/bin/env bash
# P0-2 분량 게이트. PreToolUse(Write|Edit) — 임계값을 넘으면 exit 2 로 반려한다.
#
# 왜 임계값이 비대칭인가 (docs/DESIGN.md 4장):
#   Write (새 파일)   넉넉하게  ← 새 파일 만들기를 "싸게"
#   Edit  (기존 수정) 빡빡하게  ← 기존 파일에 붙이기를 "비싸게"
#   1장의 처방을 그대로 구현한 것이다.
#
# 판정 단위 (3장, 2026-08-18 실측 확인):
#   Write 의 content    = 파일 전문. 바이트 단위로 실제 파일과 일치함을 확인
#   Edit  의 new_string = 교체 조각. 파일 전문이 아니다
#   그래서 Edit 은 "이번 턴에 얼마나 붙이는가"를 재는 것이지
#   파일이 얼마나 큰가를 재는 게 아니다.
#
# stderr 는 사람이 아니라 Claude 가 읽는다 (7장). "막았다"만 쓰면 우회를
# 시도하므로 "대신 무엇을 하라"를 반드시 넣고, 흔한 우회를 미리 막는다.
# 끄는 방법은 stderr 에 쓰지 않는다 — 그건 사람에게 하는 말이고, 모델에게
# 알려주면 게이트를 끄는 쪽으로 갈 수 있다. README 에만 적는다.
#
# set -e 를 쓰지 않는다 (7장). exit 1 은 차단이 아니라 무시된다.
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

fh_disabled "$root" guard && exit 0

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
    limit=$(fh_cfg_num "$root" '.maxNewFileLines' 250)
    ;;
  Edit)
    body=$(_field '.tool_input.new_string')
    limit=$(fh_cfg_num "$root" '.maxEditLines' 150)
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
    printf 'fe-harness: %s 를 %s줄로 쓰려 합니다. 새 파일 제한은 %s줄입니다.\n\n' \
      "${file##*/}" "$lines" "$limit"
    printf '한 번에 다 쓰지 말고 경계를 먼저 정하세요.\n'
    printf '  1. 이 파일에서 독립적으로 재사용될 단위를 고른다\n'
    printf '  2. 그 단위를 각각 별도 파일로 Write 한다\n'
    printf '  3. 원래 파일에는 조립과 배치만 남긴다\n\n'
    printf '같은 파일을 여러 번에 나눠 쓰는 우회는 하지 마세요. 문제는 파일 크기가\n'
    printf '아니라 한 턴에 사람이 검토할 수 있는 분량입니다.\n'
  else
    printf 'fe-harness: %s 에 %s줄을 한 번에 붙이려 합니다. 편집 제한은 %s줄입니다.\n\n' \
      "${file##*/}" "$lines" "$limit"
    printf '기존 파일에 큰 덩어리를 붙이는 대신:\n'
    printf '  1. 추가하려는 내용이 독립적인 단위인지 본다\n'
    printf '  2. 맞으면 새 파일로 Write 하고 여기서는 import 만 한다\n'
    printf '  3. 아니면 의미 단위로 쪼개서 여러 번 Edit 한다\n\n'
    printf '새 파일을 만드는 쪽이 기존 파일을 불리는 쪽보다 쌉니다.\n'
  fi

  [ -n "$guidance" ] && printf '\n%s\n' "$guidance"
} >&2

# exit 2 만이 차단한다. 1 은 무시된다 (7장).
exit 2
