#!/usr/bin/env bash
# P1-6 린트 피드백. PostToolUse(Write|Edit) — 고칠 수 있는 건 고치고 남은 것만 알린다.
#
# 왜 이게 퀄리티 향상인가 (docs/DESIGN.md 4장):
#   분량·컴포넌트 게이트는 "구조 열화 예방"이지 "좋은 코드 쓰기"가 아니다.
#   반면 lint 에러는 취향이 아니라 **틀린 코드**다. 그리고 Claude 는 자기가
#   방금 만든 걸 그 자리에서 보지 못한다 — 명시적으로 린터를 돌리거나
#   CI 가 몇 분 뒤에 알려줘야 안다.
#   PostToolUse 의 stderr 는 **그 턴 안에서** 간다. 피드백 루프가 분에서 초로 줄어든다.
#
# 중복 검사가 목적이 아니다. 린터를 대체하지도 않는다 — 호출할 뿐이다.
# ESLint 설정이 없는 프로젝트에서는 아무것도 하지 않는다.
#
# PostToolUse 의 exit 2 는 차단이 아니라 stderr 를 Claude 에게 보여주기다(7장).
#
# set -e 를 쓰지 않는다 (7장). macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

_field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

file=$(_field '.tool_input.file_path')
root=$(fh_root "$(_field '.cwd')")

fh_disabled "$root" lint && exit 0
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
fh_ext_allowed "$root" "$file" || exit 0
fh_excluded "$root" "$file" && exit 0

case $file in
  "$root"/*) ;;
  *) exit 0 ;;
esac

cmd=$(fh_lint_cmd "$root")
[ -n "$cmd" ] || exit 0

# 어디서 실행할지 —
#   설정한 명령  → 프로젝트 루트. `turbo lint` 나 `pnpm lint` 는 루트여야 한다
#   추론한 명령  → 파일이 속한 패키지. 모노레포에서 루트 eslint 설정이
#                  워크스페이스 패키지를 참조하면 루트에서는 해석이 안 된다
if [ -n "$(fh_cfg "$root" '.lint')" ]; then
  workdir=$root
else
  workdir=$(fh_package_dir "$root" "$file")
fi

# --fix 로 고칠 수 있는 건 고쳐지고, 남은 것만 출력에 남는다.
output=$( cd "$workdir" && sh -c "$cmd \"\$1\"" sh "$file" 2>&1 )
status=$?

[ "$status" -eq 0 ] && exit 0
[ -n "$output" ] || exit 0

# **exit 1 만 "린트 문제"로 취급한다.**
# ESLint 는 1 이 lint 문제, 2 가 설정·CLI 오류다. 그 외 코드는 린터가 아예
# 못 돌았다는 뜻이고, 그걸 코드 문제로 보고하면 Claude 가 존재하지 않는
# 문제를 고치려 든다 — 훅이 낼 수 있는 최악의 거짓말이다.
#
# 실제로 겪었다 (2026-08-18): 플래그 하나가 안 맞아 죽은 걸 "린트 문제"로
# 보고했다. 확신이 없으면 아무것도 안 하는 게 낫다(6장 3단 폴백의 원칙).
if [ "$status" -ne 1 ]; then
  exit 0
fi

# 설정과 파일이 안 맞아서 나는 에러도 코드 문제가 아니다.
# type-aware ESLint(`parserOptions.project`)는 tsconfig include 밖의 파일에
# "ESLint was configured to run on ... TSConfig does not include this file" 을 낸다.
# Claude 가 include 밖에 파일을 만드는 건 흔한 일이고, 이걸 코드 문제로
# 보고하면 고칠 수 없는 걸 고치라고 시키는 셈이다 (2026-08-18 실측).
case $output in
  *'ESLint was configured to run on'*) exit 0 ;;
esac

{
  printf 'fe-harness: %s 에 린트 문제가 남았습니다 (자동 수정 후).\n\n' "${file##*/}"
  printf '%s\n' "$output"
  printf '\n지금 고치세요. CI 까지 가면 몇 분 뒤에야 알게 됩니다.\n'
} >&2

exit 2
