#!/usr/bin/env bash
# 컴포넌트 개수 — 신호. PostToolUse(Write|Edit) — 경고만 한다. 차단하지 않는다.
#
# 왜 차단이 아닌가:
#   실측에서 현업 저장소의 정상 `.tsx` 중 5~31% 가 컴포넌트 2개 이상이었고,
#   막히는 것들이 정당한 패턴이었다 — 아이콘 래퍼 27개를 모은 배럴, 본체와
#   함께 둔 표현용 래퍼. **셀 수 있지만 그 개수가 문제인지는 읽어야 안다.**
#   그래서 차단(guard-components.sh)은 폐기하고 이 신호만 남겼다.
#   판단은 review 역할이 한다.
#
# PostToolUse 의 exit 2 는 차단이 아니라 stderr 를 Claude 에게 보여주는 것이다.
# 이미 써진 뒤이므로 문구는 "돌아가서 보라"여야 한다.
#
# Write 도 본다. 차단 훅이 사라졌으므로 여기가 유일한 컴포넌트 신호다.
#
# set -e 를 쓰지 않는다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"
# shellcheck source=lib-detect.sh
. "$SCRIPT_DIR/lib-detect.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

_field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

case $(_field '.tool_name') in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file=$(_field '.tool_input.file_path')
root=$(fh_root "$(_field '.cwd')")

fh_disabled "$root" signals && exit 0
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
fh_ext_allowed "$root" "$file" || exit 0
fh_excluded "$root" "$file" && exit 0

count=$(fh_count_components < "$file")
limit=$(fh_cfg_num "$root" '.signals.maxComponentsPerFile' 1)

[ "$count" -gt "$limit" ] || exit 0

names=$(fh_list_components < "$file" | paste -sd , - | sed 's/,/, /g')

{
  printf 'fe-harness 경고: %s 에 컴포넌트가 %s개가 됐습니다. 권장은 %s개입니다.\n' \
    "${file##*/}" "$count" "$limit"
  printf '  발견: %s\n\n' "$names"
  printf '방금 편집으로 파일이 커졌습니다. 지금 나누는 게 나중보다 쌉니다 —\n'
  printf '주 컴포넌트만 남기고 나머지는 별도 파일로 옮기세요.\n'
} >&2

# PostToolUse 의 exit 2 = stderr 를 Claude 에게 전달. 차단이 아니다.
exit 2
