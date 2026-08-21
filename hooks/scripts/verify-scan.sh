#!/usr/bin/env bash
# verify 확장 — 중복·죽은 코드를 결정적으로 잰다. docs/DESIGN.md 「분류 축」 · 「루프 구조」.
#
# 왜 에이전트가 아니라 CLI 인가:
#   중복과 죽은 코드는 **셀 수 있고 동시에 "틀렸다"고 단정할 수 있다.**
#   "셀 수 있는가"만으로 차단을 정하면 정상 코드를 막는다는 걸 실측으로 배웠지만,
#   중복·죽은 코드는 셀 수 있고 동시에 틀렸다고 단정할 수 있다. 이건 세는 게 맞다.
#
# 두 가지 모드 (이중 루프):
#   delta  이전 커밋 대비 증감. 내부 루프(커밋)용.
#          기존 저장소에 이미 중복이 200건이면 절대값은 의미가 없다.
#          "이번에 3건 늘었다"가 의미가 있다.
#   full   전체 스캔. 외부 루프(푸시)용.
#          델타는 커밋 A 와 C 사이에 생긴 중복을 못 본다 — 각 커밋 시점에는
#          증가가 없기 때문이다. 여기서만 잡힌다.
#
# 사용: verify-scan.sh <delta|full> [기준_ref]
#   stdout 에 사람이 읽는 요약, 종료 코드는 언제나 0.
#   이 스크립트는 아무것도 차단하지 않는다 — 재서 알릴 뿐이다.
#
# set -e 를 쓰지 않는다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

mode=${1:-delta}
base_ref=${2:-HEAD~1}

command -v jq >/dev/null 2>&1 || exit 0

root=$(fh_root "")
cd "$root" 2>/dev/null || exit 0

fh_disabled "$root" verify && exit 0

dup_cmd=$(fh_cfg "$root" '.verify.duplication')
dead_cmd=$(fh_cfg "$root" '.verify.deadcode')

# 명시된 것만 돈다. 추론하지 않는다 — 확신 없이 실행해서 개발을 막는 것보다
# 아무것도 안 하는 게 낫고, 추론한 명령이 몇 분짜리일 수도 있다.
[ -n "$dup_cmd" ] || [ -n "$dead_cmd" ] || exit 0

# 도구를 돌려 "건수"를 낸다. 못 돌면 빈 문자열 — 0 이 아니다.
#
# 0 과 "못 쟀다"를 구분하는 게 핵심이다. 이걸 섞으면 도구가 죽었을 때
# "중복이 사라졌다"고 보고하게 된다. **훅의 최악은 차단이 아니라 거짓말이다.**
_count() {
  local cmd=$1 out rc
  out=$(eval "$cmd" 2>/dev/null)
  rc=$?
  # 실행 자체가 실패했으면 못 잰 것이다. 리포터가 발견 시 non-zero 로
  # 끝내는 경우가 있어 출력이 있으면 통과로 본다.
  if [ $rc -ne 0 ] && [ -z "$out" ]; then
    return 1
  fi
  printf '%s' "$out" | jq -r '
    if type == "object" then
      (.statistics.total.clones // .duplicates // (.issues | length?) // 0)
    elif type == "array" then length
    else 0 end
  ' 2>/dev/null || return 1
}

report=""

_measure() {
  local label=$1 cmd=$2 now before delta
  [ -n "$cmd" ] || return 0

  now=$(_count "$cmd") || {
    report="${report}  $label: 재지 못했습니다 (명령이 실행되지 않음)"$'\n'
    return 0
  }

  if [ "$mode" = full ]; then
    report="${report}  $label: 전체 ${now}건"$'\n'
    return 0
  fi

  # delta — 기준 커밋의 워크트리에서 같은 명령을 돌려 비교한다.
  #
  # 비교에 실패하면 **조용히 넘어간다.** 절대값을 대신 내지 않는다 —
  # 기존 저장소에 이미 중복이 200건이면 그 숫자는 행동으로 옮길 수 없고,
  # 그래서 애초에 델타를 택했다. 못 재면 할 말이 없는 것이다.
  # 첫 커밋(HEAD~1 없음)이나 아카이브가 안 되는 경우가 여기 걸린다.
  # 설정이 잘못됐는지는 full 모드(푸시)에서 절대값으로 드러난다.
  before=$(_count_at "$base_ref" "$cmd") || return 0

  delta=$((now - before))
  if [ "$delta" -gt 0 ]; then
    report="${report}  $label: ${before} → ${now}건 (+${delta}) ← 이번 변경이 늘렸습니다"$'\n'
  elif [ "$delta" -lt 0 ]; then
    report="${report}  $label: ${before} → ${now}건 (${delta})"$'\n'
  fi
  # 변화가 없으면 아무것도 적지 않는다. 조용한 게 기본이다.
}

# 기준 ref 의 트리를 임시 워크트리에 꺼내 같은 명령을 돌린다.
# 현재 워크트리를 건드리지 않는 것이 중요하다 — 사람이 작업 중이다.
_count_at() {
  local ref=$1 cmd=$2 tmp result
  git rev-parse --verify --quiet "$ref" >/dev/null 2>&1 || return 1
  tmp=$(mktemp -d) || return 1
  if ! git archive "$ref" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  # 의존성 없이 도는 도구만 비교할 수 있다. node_modules 를 링크해 준다.
  [ -d "$root/node_modules" ] && ln -s "$root/node_modules" "$tmp/node_modules" 2>/dev/null
  result=$(cd "$tmp" && _count "$cmd")
  local rc=$?
  rm -rf "$tmp"
  [ $rc -eq 0 ] || return 1
  printf '%s' "$result"
}

_measure "중복" "$dup_cmd"
_measure "죽은 코드" "$dead_cmd"

[ -n "$report" ] || exit 0

if [ "$mode" = full ]; then
  printf 'fe-harness verify (브랜치 전체):\n%s' "$report"
else
  printf 'fe-harness verify (이번 변경):\n%s' "$report"
fi

guidance=$(fh_cfg "$root" '.guidance')
[ -n "$guidance" ] && printf '%s\n' "$guidance"

exit 0
