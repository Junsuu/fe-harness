#!/usr/bin/env bash
# P0-1 포맷 훅. PostToolUse(Write|Edit) — 방금 편집된 파일 1개만 포맷한다.
#
# 왜 P0 인가 (docs/DESIGN.md 4장):
#   Claude 가 Write 로 만든 파일은 에디터의 저장 이벤트를 안 거친다.
#   format-on-save 가 걸려 있어도 적용되지 않는다. 포맷 안 된 코드가 섞인
#   diff 는 사람이 검토할 수 없고, 그게 이 프로젝트의 목표를 정면으로 깬다.
#
# 왜 저장소 전체가 아니라 파일 1개인가:
#   PostToolUse 는 매 편집마다 돈다. 느리면 결국 끄게 된다 (7장).
#
# 이 훅은 절대 차단하지 않는다. 무슨 일이 있어도 exit 0.
# 포맷 실패로 개발이 멈추면 하네스가 아니라 방해물이다.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

# jq 가 없으면 전체 no-op. 확신 없이 뭔가 하는 것보다 낫다.
command -v jq >/dev/null 2>&1 || exit 0

file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

payload_cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
root=$(fh_root "$payload_cwd")

fh_disabled "$root" format && exit 0

# 프로젝트 밖의 파일은 건드리지 않는다.
case $file in
  "$root"/*) ;;
  *) exit 0 ;;
esac

cmd=$(fh_format_cmd "$root")
[ -n "$cmd" ] || exit 0

# 파일 경로는 인자로 넘긴다 — 명령 문자열에 끼워 넣지 않는다 (쿼팅 사고 방지).
# 출력은 버린다. PostToolUse 의 stdout 은 컨텍스트로 가지 않고, 포매터 잡음이
# transcript 를 채우면 훅을 꺼버리게 된다.
( cd "$root" && sh -c "$cmd \"\$1\"" sh "$file" ) >/dev/null 2>&1

exit 0
