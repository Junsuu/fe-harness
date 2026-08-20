#!/usr/bin/env bash
# 품질 게이트. Stop — 타입체크·테스트가 통과하기 전엔 턴을 못 끝낸다.
#
# 이것도 "예방"이 아니라 퀄리티 향상이다. 안 되는 코드가 턴을 넘어가지 않는다.
#
# **추론하지 않는다.** 3단 폴백의 2번(추론)을 여기서만 건너뛴다.
#   이 훅은 차단한다. 확신 없이 추론한 명령으로 개발을 막는 건
#   6장의 원칙("확신 없이 실행해서 개발을 막는 것보다 아무것도 안 하는 게 낫다")에
#   정면으로 어긋난다. 게다가 추론한 test 명령이 몇 분짜리일 수도 있다.
#   .fe-harness.json 에 typecheck / test 를 **명시했을 때만** 돈다.
#
# 무한 루프 방지 (docs/DESIGN.md 「훅 작성 시 반드시 지킬 것」):
#   stop_hook_active 가 true 면 즉시 통과시킨다. 이미 한 번 막았다는 뜻이다.
#   그래도 연속 8회 차단하면 Claude Code 가 이 훅을 무시한다.
#
# 변경이 없으면 돌지 않는다. 질문만 한 턴에서 tsc 를 돌리는 건 낭비고,
# 느린 훅은 결국 꺼진다.
#
# set -e 를 쓰지 않는다 — exit 1 은 차단이 아니다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

_field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

# 이미 한 번 막았으면 그냥 보낸다. 안 그러면 무한 루프다.
[ "$(_field '.stop_hook_active')" = "true" ] && exit 0

root=$(fh_root "$(_field '.cwd')")
fh_disabled "$root" gate && exit 0

typecheck=$(fh_cfg "$root" '.verify.typecheck')
test_cmd=$(fh_cfg "$root" '.verify.test')
[ -n "$typecheck$test_cmd" ] || exit 0

# 작업 트리에 변경이 없으면 검사할 것도 없다.
# git 저장소가 아니면 판단할 수 없으므로 그냥 돈다.
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  changed=$(git -C "$root" status --porcelain 2>/dev/null | head -1)
  [ -n "$changed" ] || exit 0
fi

failed=''
output=''

run_step() {
  local label=$1 cmd=$2 out status
  [ -n "$cmd" ] || return 0
  out=$( cd "$root" && sh -c "$cmd" 2>&1 )
  status=$?
  [ "$status" -eq 0 ] && return 0
  failed="$failed $label"
  output="$output
── $label ──
$out"
}

run_step 타입체크 "$typecheck"
run_step 테스트 "$test_cmd"

[ -n "$failed" ] || exit 0

{
  printf 'fe-harness: 통과하지 못한 검사가 있습니다 —%s\n' "$failed"
  printf '%s\n\n' "$output"
  printf '턴을 끝내기 전에 고치세요. 검사를 우회하거나 비활성화하지 마세요.\n'
} >&2

# Stop 훅의 exit 2 는 종료를 막는다.
exit 2
