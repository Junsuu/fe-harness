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

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
