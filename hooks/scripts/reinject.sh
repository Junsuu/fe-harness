#!/usr/bin/env bash
# P1-7 규칙 재주입. SessionStart — stdout 이 그대로 컨텍스트에 들어간다.
#
# stdout 이 컨텍스트로 가는 이벤트는 SessionStart · UserPromptSubmit ·
# UserPromptExpansion 셋뿐이다(7장). 그래서 이게 **유일한 예방 채널**이다.
#
# 두 가지 일을 동시에 한다:
#   1) 컴팩션으로 규칙이 희석된 뒤 다시 넣기 (원래 목적)
#   2) 쓰기 전에 임계값을 알려주기 (예방)
#
# 훅은 반려밖에 못 한다 — 그건 교정이다. 모델이 처음부터 제대로 쓰게 하려면
# 쓰기 전에 컨텍스트에 있어야 하고, 그건 스킬로는 안 된다(스킬은 호출해야
# 로드된다). 4장 「예방은 스킬의 일이 아니다」 참조.
#
# **짧게 유지한다.** 여기 넣는 만큼 매 세션 컨텍스트를 먹는다.
# 절차가 필요하면 스킬로 가야지 이 자리를 늘리면 안 된다.
#
# set -e 를 쓰지 않는다 (7장). macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

root=$(fh_root "$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)")

fh_disabled "$root" inject && exit 0

# 사용자가 문구를 직접 정했으면 그것만 낸다.
custom=$(fh_cfg "$root" '.inject')
if [ -n "$custom" ]; then
  printf '%s\n' "$custom"
  exit 0
fi

# 아니면 실제 임계값을 그대로 알려준다. 훅이 무엇으로 막을지 미리 아는 게 낫다.
new_lines=$(fh_cfg_num "$root" '.maxNewFileLines' 250)
edit_lines=$(fh_cfg_num "$root" '.maxEditLines' 80)
components=$(fh_cfg_num "$root" '.maxComponentsPerFile' 1)

printf 'fe-harness 가 켜져 있습니다. 프론트엔드 소스에 다음이 강제됩니다 — '
printf '컴포넌트는 파일당 %s개, 새 파일 Write 는 %s줄, 한 번의 Edit 는 %s줄까지.\n' \
  "$components" "$new_lines" "$edit_lines"
printf '막힌 뒤에 쪼개지 말고 처음부터 파일을 나눠서 쓰세요. '
printf '새 파일을 만드는 쪽이 기존 파일을 불리는 쪽보다 쌉니다.\n'

exit 0
