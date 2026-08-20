#!/usr/bin/env bash
# 루프 방아쇠. PostToolUse(Bash) + asyncRewake — 커밋·푸시 시점에 루프를 깨운다.
#
# 이 스크립트가 하지 않는 것 (docs/DESIGN.md 「훅 구조 — 절차는 한 곳에만」):
#   순서 · 역할 해석 · 판단을 갖지 않는다. **절차의 정의는 commands/lap.md 하나뿐이다.**
#   훅에 절차가 생기면 셸 한 벌과 마크다운 한 벌이 되고, 둘은 반드시 갈린다.
#
# 그래서 하는 일은 둘뿐이다:
#   1. 지금 깨울 만한 커밋인가 판단 (대상 파일이 바뀌었나)
#   2. 셸로 가능한 결정적 계산(verify-scan)을 미리 돌려 결과를 붙인다
#   나머지는 stderr 로 "/lap 절차를 이어서 하라"고 말한다.
#
# asyncRewake 는 백그라운드로 돌기 때문에 사람의 턴을 막지 않는다.
# 커밋은 이미 끝났고, 지적은 다음 턴에 온다. 이게 비싼 검사를 넣을 수 있는 이유다.
#
# PostToolUse 의 exit 2 는 차단이 아니라 stderr 를 모델에게 보여주는 것이다.
# 여기서는 그 stderr 가 rewake 본문이 된다.
#
# 사용: loop-trigger.sh <commit|push>
#
# set -e 를 쓰지 않는다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

mode=${1:-commit}

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

root=$(fh_root "$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)")
cd "$root" 2>/dev/null || exit 0

fh_disabled "$root" loop && exit 0

# 트리거는 개별로 끌 수 있다. 값이 없으면 켜져 있는 것으로 본다.
[ "$(fh_cfg_bool "$root" ".trigger.$mode" true)" = "false" ] && exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 무엇이 바뀌었나. 커밋은 방금 만들어진 것, 푸시는 브랜치 전체.
if [ "$mode" = push ]; then
  range=$(git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 && printf '@{u}..HEAD' || printf 'HEAD~1..HEAD')
else
  range=HEAD~1..HEAD
fi
changed=$(git diff --name-only "$range" 2>/dev/null) || exit 0
[ -n "$changed" ] || exit 0

# 프론트엔드 소스가 안 바뀐 커밋은 깨우지 않는다.
# 문서·설정만 고친 커밋에 FE 리뷰를 돌리는 건 토큰만 쓰고 잡음만 낸다.
target=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  fh_ext_allowed "$root" "$f" || continue
  fh_excluded "$root" "$root/$f" && continue
  target=1
  break
done <<EOF
$changed
EOF
[ "$target" = 1 ] || exit 0

# 셸로 가능한 결정적 계산만 미리 돌린다. 판단은 모델 몫이다.
# 커밋 훅은 커밋이 끝난 뒤 돌므로 기준이 HEAD~1 이다 (아직 커밋 안 한 상태에서
# 도는 /lap 과 다르다 — 거기서는 HEAD 가 기준이다).
if [ "$mode" = push ]; then
  scan=$("$SCRIPT_DIR/verify-scan.sh" full 2>/dev/null)
else
  scan=$("$SCRIPT_DIR/verify-scan.sh" delta HEAD~1 2>/dev/null)
fi

{
  if [ "$mode" = push ]; then
    printf 'fe-harness 외부 루프 — 푸시된 브랜치 전체를 본다.\n\n'
  else
    printf 'fe-harness 내부 루프 — 방금 커밋된 변경을 본다.\n\n'
  fi

  if [ -n "$scan" ]; then
    printf '%s\n' "$scan"
  else
    printf '결정적 검사에서는 새로 걸린 것이 없다.\n\n'
  fi

  # 절차를 여기에 적지 않는다. 한 곳만 가리킨다.
  printf 'fe-harness:lap 스킬을 불러 '
  if [ "$mode" = push ]; then
    printf '**외부 루프**의 review · learn 단계를 이어서 수행한다.\n'
  else
    printf '**내부 루프**의 review · refine · learn 단계를 이어서 수행한다.\n'
  fi
  printf 'verify 단계는 위 결과로 대신한다 — 같은 검사를 다시 돌리지 않는다.\n'

  guidance=$(fh_cfg "$root" '.guidance')
  [ -n "$guidance" ] && printf '\n%s\n' "$guidance"
} >&2

exit 2
