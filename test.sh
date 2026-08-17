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

# --- 포맷 훅 (P0-1) ------------------------------------------------------
# 훅을 직접 실행해서 확인한다. 경로 오타나 조용한 no-op 이 제일 잡기 어렵다.

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 대상 파일에 마커를 붙이는 가짜 포매터
cat > "$TMP/fake-fmt.sh" <<'FMT'
#!/usr/bin/env bash
printf 'FORMATTED\n' >> "$1"
FMT
chmod +x "$TMP/fake-fmt.sh"

# 설정과 대상 파일을 준비하고 format.sh 에 payload 를 물린다.
# 결과는 전역 fmt_hits / fmt_exit 로 낸다 — 명령치환으로 감싸면 서브셸이라
# 함수 안에서 잡은 종료 코드가 사라진다.
fmt_hits=0
fmt_exit=0

run_format() {
  local root=$1 config=$2
  local target=${3:-$root/a.tsx}
  printf 'const A = 1;\n' > "$target"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$root/.fe-harness.json"
  else
    rm -f "$root/.fe-harness.json"
  fi
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' "$root" "$target" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/format.sh"
  fmt_exit=$?
  fmt_hits=$(grep -c 'FORMATTED' "$target")
}

expect_format() {
  local label=$1 want=$2 config=$3 target=${4:-}
  run_format "$TMP" "$config" "$target"
  # 이 훅은 무슨 일이 있어도 exit 0 이어야 한다.
  if [ "$fmt_hits" = "$want" ] && [ "$fmt_exit" -eq 0 ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s 포맷실행=%s exit=%s\n' "$label" "$fmt_hits" "$fmt_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s 포맷실행=%s exit=%s (기대 %s / exit 0)\n' "$label" "$fmt_hits" "$fmt_exit" "$want"
  fi
}

# 추론 실패 → 조용히 통과. 훅이 확신 없이 뭔가 실행하면 안 된다.
expect_format '포매터없음-무동작' 0 ''
# 설정이 있으면 무조건 신뢰
expect_format '설정지정-실행' 1 '{"format":"./fake-fmt.sh"}'
# 끌 수 있어야 한다 — 끌 방법이 없으면 사용자는 플러그인을 삭제한다
expect_format 'disable.format-무동작' 0 '{"format":"./fake-fmt.sh","disable":{"format":true}}'
# 프로젝트 밖의 파일은 건드리지 않는다
expect_format '프로젝트밖-무동작' 0 '{"format":"./fake-fmt.sh"}' "$TMP.outside.tsx"
rm -f "$TMP.outside.tsx"

# --- 분량 게이트 관찰 모드 (P0-2) ----------------------------------------
# 지금은 아무것도 막지 않는다. 확인할 것은 두 가지 —
# 무슨 일이 있어도 exit 0 인가, payload 를 온전히 떠내는가.

OBS=$TMP/observe

run_guard() {
  local config=$1 body=$2
  rm -rf "$OBS"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/a.tsx","content":%s}}' \
    "$TMP" "$TMP" "$(printf '%s' "$body" | jq -Rs .)" \
    | env -u CLAUDE_PROJECT_DIR FE_HARNESS_OBSERVE_DIR="$OBS" "$ROOT/hooks/scripts/guard-size.sh"
  guard_exit=$?
  guard_files=$(ls "$OBS"/payload-*.json 2>/dev/null | wc -l | tr -d ' ')
}

expect_guard() {
  local label=$1 want_files=$2 config=$3 body=$4
  run_guard "$config" "$body"
  if [ "$guard_files" = "$want_files" ] && [ "$guard_exit" -eq 0 ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s payload=%s exit=%s\n' "$label" "$guard_files" "$guard_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s payload=%s exit=%s (기대 %s / exit 0)\n' \
      "$label" "$guard_files" "$guard_exit" "$want_files"
  fi
}

expect_guard '관찰-payload기록' 1 '' 'const A = 1;'
expect_guard 'disable.guard-무동작' 0 '{"disable":{"guard":true}}' 'const A = 1;'

# 떠낸 payload 에서 원문이 손실 없이 복원되는가.
# 훅이 스스로를 검증할 수는 없지만, 파이프를 타는 동안 깨지지 않는지는 볼 수 있다.
big=$(awk 'BEGIN { for (i = 1; i <= 400; i++) print "const v" i " = " i ";" }')
run_guard '' "$big"
restored=$(jq -r '.tool_input.content' "$OBS"/payload-*.json | awk 'END { print NR }')
logged=$(awk -F'\t' '{ print $3 }' "$OBS/observe.log" | head -1)
if [ "$restored" = "400" ] && [ "$logged" = "lines=400" ] && [ "$guard_exit" -eq 0 ]; then
  pass=$((pass + 1))
  printf 'ok    %-32s 복원=%s줄 기록=%s\n' '관찰-400줄무손실' "$restored" "$logged"
else
  fail=$((fail + 1))
  printf 'FAIL  %-32s 복원=%s줄 기록=%s (기대 400 / lines=400)\n' \
    '관찰-400줄무손실' "$restored" "$logged"
fi

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
