#!/usr/bin/env bash
# P0-2 분량 게이트 — 현재 **관찰 모드**. 아무것도 막지 않는다.
#
# 목적 (docs/DESIGN.md 8장 ①):
#   PreToolUse 의 tool_input 에 쓰려는 코드가 전문으로 오는지 확인한다.
#   전문이면 줄 수를 세서 반려할 수 있고, 잘려 오면 설계를 바꿔야 한다.
#
#   버릴 훅을 따로 심는 대신 진짜 훅의 첫 버전으로 확인한다 — 어차피
#   플러그인 설치 때 세션 재시작이 필요하니 그 한 번에 합친다.
#
# 관찰 결과는 여기에 쌓인다 (저장소 밖 — 절대 커밋되지 않는다):
#   ${FE_HARNESS_OBSERVE_DIR:-$TMPDIR/fe-harness-observe}
#     payload-<시각>-<pid>.json   훅이 받은 stdin 전문
#     observe.log                 한 줄 요약
#
# 다음 단계에서 여기에 임계값 비교와 exit 2 를 붙인다 (9장 5번).
# 그때 관찰 기능은 .fe-harness.json 의 observe 플래그로 내린다.
#
# set -e 를 쓰지 않는다 (7장). macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

# jq 가 없으면 전체 no-op.
command -v jq >/dev/null 2>&1 || exit 0

payload_cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
root=$(fh_root "$payload_cwd")

fh_disabled "$root" guard && exit 0

dir=${FE_HARNESS_OBSERVE_DIR:-${TMPDIR:-/tmp}/fe-harness-observe}
mkdir -p "$dir" 2>/dev/null || exit 0

stamp=$(date +%Y%m%d-%H%M%S)
printf '%s' "$payload" > "$dir/payload-$stamp-$$.json"

tool=$(printf '%s' "$payload" | jq -r '.tool_name // "?"' 2>/dev/null)
target=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // "?"' 2>/dev/null)
keys=$(printf '%s' "$payload" | jq -rc '.tool_input | keys' 2>/dev/null)

# Write 는 content, Edit 는 new_string. 둘 다 없으면 빈 문자열.
body=$(printf '%s' "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""' 2>/dev/null)
lines=$(printf '%s' "$body" | awk 'END { print NR }')
bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')

printf '%s\t%s\tlines=%s\tbytes=%s\tkeys=%s\t%s\n' \
  "$stamp" "$tool" "$lines" "$bytes" "$keys" "$target" >> "$dir/observe.log"

# 관찰 모드 — 무슨 일이 있어도 통과시킨다.
exit 0
