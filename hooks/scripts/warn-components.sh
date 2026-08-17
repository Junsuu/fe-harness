#!/usr/bin/env bash
# P0-3 인라인 컴포넌트 — Edit 경로. PostToolUse(Edit) — 경고만 한다.
#
# 왜 경고인가:
#   PostToolUse 는 이미 써진 뒤라 되돌릴 수 없다. 그런데 Edit 은 조각만
#   오므로(3장) PreToolUse 에서는 파일에 컴포넌트가 몇 개가 되는지 알 수 없다.
#   여기서는 **완성된 파일을 읽어서** 정확히 셀 수 있다.
#   정확하지만 늦거나, 이르지만 부정확하거나 — 후자를 택했다.
#
# PostToolUse 의 exit 2 는 차단이 아니라 stderr 를 Claude 에게 보여주는 것이다(7장).
# 그러니 문구는 "돌아가서 고쳐라"여야 한다. 이미 벌어진 일이니까.
#
# Write 는 guard-components.sh 가 PreToolUse 에서 이미 반려했으므로 건너뛴다.
#
# set -e 를 쓰지 않는다 (7장). macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"
# shellcheck source=lib-detect.sh
. "$SCRIPT_DIR/lib-detect.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

_field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

[ "$(_field '.tool_name')" = Edit ] || exit 0

file=$(_field '.tool_input.file_path')
root=$(fh_root "$(_field '.cwd')")

fh_disabled "$root" warn && exit 0
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
fh_ext_allowed "$root" "$file" || exit 0
fh_excluded "$root" "$file" && exit 0

count=$(fh_count_components < "$file")
limit=$(fh_cfg_num "$root" '.maxComponentsPerFile' 1)

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
