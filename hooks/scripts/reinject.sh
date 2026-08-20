#!/usr/bin/env bash
# guide 주입. SessionStart — stdout 이 그대로 컨텍스트에 들어간다.
#
# stdout 이 컨텍스트로 가는 이벤트는 SessionStart · UserPromptSubmit ·
# UserPromptExpansion 셋뿐이다 (docs/DESIGN.md 5장). 그래서 이게 **유일한 예방 채널**이다.
#
# 두 가지 일을 동시에 한다:
#   1) 컴팩션으로 규칙이 희석된 뒤 다시 넣기 (원래 목적)
#   2) 쓰기 전에 임계값을 알려주기 (예방)
#
# 훅의 지적은 쓴 뒤에 온다 — 그건 교정이다. 모델이 처음부터 제대로 쓰게 하려면
# 쓰기 전에 컨텍스트에 있어야 하고, 그건 스킬로는 안 된다(스킬은 호출해야
# 로드된다). docs/DESIGN.md 5장 「스킬로는 예방이 안 된다」 참조.
#
# **짧게 유지한다.** 여기 넣는 만큼 매 세션 컨텍스트를 먹는다.
# 절차가 필요하면 스킬로 가야지 이 자리를 늘리면 안 된다.
#
# set -e 를 쓰지 않는다 (docs/DESIGN.md 11장). macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

root=$(fh_root "$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)")

fh_disabled "$root" guide && exit 0

# 0.1.x 평면 스키마가 남아 있으면 먼저 알린다. 옛 키는 이제 읽지 않으므로
# 말해주지 않으면 사용자는 자기 설정이 도는 줄 안다.
legacy=$(fh_legacy_keys "$root")
if [ -n "$legacy" ]; then
  printf 'fe-harness: .fe-harness.json 의 옛 키(%s)는 0.2.0 부터 읽지 않습니다. ' "$legacy"
  printf 'format/lint/typecheck/test 는 verify 아래로, max* 는 signals 아래로 옮기세요. '
  printf '.fe-harness.example.json 참고.\n'
fi

# 사용자가 문구를 직접 정했으면 그것만 낸다.
custom=$(fh_cfg "$root" '.inject')
if [ -n "$custom" ]; then
  printf '%s\n' "$custom"
  exit 0
fi

# v2 에는 차단하는 훅이 없다. 전부 신호다.
# 안 막는 것을 막는다고 말하면 그게 곧 거짓말이고, 모델은 그 말을 믿는다.
new_lines=$(fh_cfg_num "$root" '.signals.maxNewFileLines' 250)
edit_lines=$(fh_cfg_num "$root" '.signals.maxEditLines' 80)
components=$(fh_cfg_num "$root" '.signals.maxComponentsPerFile' 1)

printf 'fe-harness 가 켜져 있습니다. 프론트엔드 소스에 대해 새 파일 %s줄, ' "$new_lines"
printf '한 번의 Edit %s줄, 파일당 컴포넌트 %s개를 넘으면 신호를 냅니다 — 차단은 하지 않습니다.\n' \
  "$edit_lines" "$components"
printf '막힌 뒤에 쪼개지 말고 처음부터 나눠서 쓰세요. '
printf '커밋 전에 /lap 을 부르면 리뷰 · 개선 · 기록까지 한 바퀴 돕니다.\n'

exit 0
