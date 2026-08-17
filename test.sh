#!/usr/bin/env bash
# fe-harness 탐지 로직 회귀 테스트.
# lib-detect.sh 의 정규식을 고칠 때마다 돌린다.
# 새 오탐/미탐을 발견하면 그 코드를 fixtures/ 에 추가하고 여기에 기대값을 박는다.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=hooks/scripts/lib-detect.sh
. "$ROOT/hooks/scripts/lib-detect.sh"

pass=0
fail=0

expect_components() {
  local file=$1 want=$2 got
  got=$(fh_count_components < "$ROOT/fixtures/$file")
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s components=%s\n' "$file" "$got"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s components=%s (기대 %s)\n' "$file" "$got" "$want"
  fi
}

expect_flag_props() {
  local file=$1 want=$2 got
  got=$(fh_flag_props 2 < "$ROOT/fixtures/$file")
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s flag-props=%s\n' "$file" "${got:-(없음)}"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s flag-props=%s (기대 %s)\n' "$file" "${got:-(없음)}" "${want:-(없음)}"
  fi
}

# --- 컴포넌트 개수 -------------------------------------------------------
expect_components negative-non-components.tsx 0
expect_components positive-function-decls.tsx 4
expect_components positive-const-components.tsx 4
expect_components positive-hoc.tsx 2
expect_components mixed-single-component.tsx 1
expect_components inline-two-components.tsx 2

# --- flag props ----------------------------------------------------------
expect_flag_props flag-props-many.tsx 'ToggleCardProps (boolean prop 3개)'
expect_flag_props flag-props-none.tsx ''

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
