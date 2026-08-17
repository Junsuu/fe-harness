#!/usr/bin/env bash
# P0-3 인라인 컴포넌트 게이트. PreToolUse(Write) — 초과하면 exit 2 로 반려한다.
#
# **Write 만 본다.** Edit 의 new_string 은 교체 조각이라 파일에 컴포넌트가
# 몇 개가 되는지 알 수 없다(3장). Edit 경로는 warn-components.sh 가
# PostToolUse 에서 완성된 파일을 읽어 경고한다.
#
# 왜 흔한 경로부터 막는가:
#   증상 ⑤(인라인 컴포넌트)는 대부분 새 파일을 쓸 때 생긴다. 기존 파일에
#   두 번째 컴포넌트를 Edit 으로 끼워 넣는 건 상대적으로 드물다.
#   흔한 경로는 반려하고 드문 경로는 경고로 두고 실사용 기록을 본다(11장).
#
# 임계값 의미:
#   maxComponentsPerFile 은 **허용 최대 개수**다. 기본값 1 —
#   즉 한 파일에 컴포넌트가 2개 이상이면 반려한다. 그게 4장의 의도다.
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

[ "$(_field '.tool_name')" = Write ] || exit 0

file=$(_field '.tool_input.file_path')
root=$(fh_root "$(_field '.cwd')")

fh_disabled "$root" guard && exit 0
[ -n "$file" ] || exit 0
fh_ext_allowed "$root" "$file" || exit 0
fh_excluded "$root" "$file" && exit 0

body=$(_field '.tool_input.content')
count=$(printf '%s' "$body" | fh_count_components)
limit=$(fh_cfg_num "$root" '.maxComponentsPerFile' 1)

[ "$count" -gt "$limit" ] || exit 0

names=$(printf '%s' "$body" | fh_list_components | paste -sd , - | sed 's/,/, /g')
guidance=$(fh_cfg "$root" '.guidance')

{
  printf 'fe-harness: %s 에 컴포넌트가 %s개 있습니다. 한 파일에 %s개까지입니다.\n' \
    "${file##*/}" "$count" "$limit"
  printf '  발견: %s\n\n' "$names"
  printf '재사용하지 않을 컴포넌트라도 파일을 나누세요.\n'
  printf '  1. 주 컴포넌트만 이 파일에 남긴다\n'
  printf '  2. 나머지는 각각 별도 파일로 Write 한다\n'
  printf '  3. 여기서는 import 해서 쓴다\n\n'
  printf '"여기서만 쓰니까 같이 두는 게 낫다"고 판단하지 마세요.\n'
  printf '그 판단이 쌓여서 파일이 비대해집니다.\n'
  [ -n "$guidance" ] && printf '\n%s\n' "$guidance"
} >&2

exit 2
