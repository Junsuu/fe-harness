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

# --- 분량 게이트 (P0-2) --------------------------------------------------
# 반려는 exit 2 여야 한다. exit 1 은 차단이 아니라 무시된다.

nlines() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "const v" i " = " i ";" }'; }

GUARD_ERR=$TMP/guard.stderr

run_guard() {
  local tool=$1 target=$2 body=$3 config=$4 key
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  [ "$tool" = Write ] && key=content || key=new_string
  printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s","%s":%s}}' \
    "$tool" "$TMP" "$target" "$key" "$(printf '%s' "$body" | jq -Rs .)" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/guard-size.sh" 2> "$GUARD_ERR"
  guard_exit=$?
}

# want: 0 = 통과, 2 = 반려
expect_guard() {
  local label=$1 want=$2 tool=$3 target=$4 nline=$5 config=${6:-}
  run_guard "$tool" "$target" "$(nlines "$nline")" "$config"
  if [ "$guard_exit" -eq "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s exit=%s\n' "$label" "$guard_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s exit=%s (기대 %s)\n' "$label" "$guard_exit" "$want"
  fi
}

# 비대칭 임계값 — 새 파일은 넉넉하게, 기존 수정은 빡빡하게
expect_guard 'Write-249줄-통과'      0 Write "$TMP/a.tsx" 249
expect_guard 'Write-251줄-반려'      2 Write "$TMP/a.tsx" 251
expect_guard 'Edit-79줄-통과'        0 Edit  "$TMP/a.tsx" 79
expect_guard 'Edit-81줄-반려'        2 Edit  "$TMP/a.tsx" 81

# 설정으로 조정된다
expect_guard '임계값설정-반려'        2 Write "$TMP/a.tsx" 60  '{"maxNewFileLines":50}'
expect_guard '임계값설정-통과'        0 Write "$TMP/a.tsx" 40  '{"maxNewFileLines":50}'

# 끌 수 있어야 한다
expect_guard 'disable.guard-통과'     0 Write "$TMP/a.tsx" 999 '{"disable":{"guard":true}}'

# 코드가 아닌 파일은 분량으로 막지 않는다 — 긴 문서는 정상이다
expect_guard '마크다운-통과'          0 Write "$TMP/DESIGN.md" 999
expect_guard 'JSON-통과'             0 Write "$TMP/data.json" 999

# exclude 패턴
expect_guard 'exclude-stories-통과'   0 Write "$TMP/Button.stories.tsx" 999 \
  '{"exclude":["**/*.stories.tsx"]}'
expect_guard 'exclude-깊은경로-통과'  0 Write "$TMP/src/gen/api.ts" 999 \
  '{"exclude":["src/gen/**"]}'
expect_guard 'exclude-비대상-반려'    2 Write "$TMP/src/app/api.ts" 999 \
  '{"exclude":["src/gen/**"]}'

# stderr 는 Claude 가 읽는다. "대신 무엇을 하라"가 반드시 들어가야 한다.
run_guard Write "$TMP/a.tsx" "$(nlines 300)" ''
if grep -q '별도 파일로 Write' "$GUARD_ERR" && grep -q '250줄' "$GUARD_ERR" &&
   ! grep -q 'disable' "$GUARD_ERR"; then
  pass=$((pass + 1))
  printf 'ok    %-32s 대안·임계값 포함, 끄는법 미포함\n' 'stderr-문구'
else
  fail=$((fail + 1))
  printf 'FAIL  %-32s\n' 'stderr-문구'
  sed 's/^/      /' "$GUARD_ERR"
fi

# guidance 는 프로젝트 설정에서만 온다 — 플러그인은 남의 도구를 모른다
run_guard Write "$TMP/a.tsx" "$(nlines 300)" '{"guidance":"우리 저장소 규칙 먼저 확인"}'
if grep -q '우리 저장소 규칙 먼저 확인' "$GUARD_ERR"; then
  pass=$((pass + 1))
  printf 'ok    %-32s stderr 에 덧붙음\n' 'guidance'
else
  fail=$((fail + 1))
  printf 'FAIL  %-32s guidance 가 안 붙음\n' 'guidance'
fi

# 관찰 모드는 기본 꺼짐
OBS=$TMP/observe
rm -rf "$OBS"
FE_HARNESS_OBSERVE_DIR=$OBS run_guard Write "$TMP/a.tsx" "$(nlines 10)" ''
off=$(ls "$OBS"/payload-*.json 2>/dev/null | wc -l | tr -d ' ')
rm -rf "$OBS"
FE_HARNESS_OBSERVE_DIR=$OBS run_guard Write "$TMP/a.tsx" "$(nlines 10)" '{"observe":true}'
on=$(ls "$OBS"/payload-*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$off" = "0" ] && [ "$on" = "1" ]; then
  pass=$((pass + 1))
  printf 'ok    %-32s 기본=%s observe=%s\n' '관찰모드-플래그' "$off" "$on"
else
  fail=$((fail + 1))
  printf 'FAIL  %-32s 기본=%s observe=%s (기대 0 / 1)\n' '관찰모드-플래그' "$off" "$on"
fi

# --- 인라인 컴포넌트 (P0-3) ----------------------------------------------
# Write 는 PreToolUse 반려, Edit 는 PostToolUse 경고.

# 개수 세는 함수와 이름 뽑는 함수가 어긋나면 반려 메시지가 거짓말을 한다.
for f in "$ROOT"/fixtures/*.tsx; do
  c=$(fh_count_components < "$f")
  l=$(fh_list_components < "$f" | grep -c . || true)
  if [ "$c" = "$l" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s 개수=%s 목록=%s\n' "개수-목록일치 $(basename "$f")" "$c" "$l"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s 개수=%s 목록=%s\n' "개수-목록일치 $(basename "$f")" "$c" "$l"
  fi
done

COMP_ERR=$TMP/comp.stderr

run_guard_components() {
  local target=$1 src=$2 config=$3
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s","content":%s}}' \
    "$TMP" "$target" "$(jq -Rs . < "$src")" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/guard-components.sh" 2> "$COMP_ERR"
  comp_exit=$?
}

expect_components() {
  local label=$1 want=$2 fixture=$3 config=${4:-}
  run_guard_components "$TMP/a.tsx" "$ROOT/fixtures/$fixture" "$config"
  if [ "$comp_exit" -eq "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s exit=%s\n' "$label" "$comp_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s exit=%s (기대 %s)\n' "$label" "$comp_exit" "$want"
  fi
}

expect_components 'Write-1개-통과'      0 mixed-single-component.tsx
expect_components 'Write-2개-반려'      2 inline-two-components.tsx
expect_components 'Write-0개-통과'      0 negative-non-components.tsx
expect_components '허용2로완화-통과'    0 inline-two-components.tsx '{"maxComponentsPerFile":2}'
expect_components 'disable.guard-통과'  0 inline-two-components.tsx '{"disable":{"guard":true}}'
expect_components 'exclude-통과'        0 inline-two-components.tsx '{"exclude":["**/a.tsx"]}'

# 반려 메시지에 컴포넌트 이름이 실제로 들어가는가
run_guard_components "$TMP/a.tsx" "$ROOT/fixtures/inline-two-components.tsx" ''
if grep -q 'EmptyState' "$COMP_ERR" && grep -q 'OrderList' "$COMP_ERR"; then
  pass=$((pass + 1))
  printf 'ok    %-32s 이름 포함\n' 'stderr-컴포넌트이름'
else
  fail=$((fail + 1))
  printf 'FAIL  %-32s\n' 'stderr-컴포넌트이름'
  sed 's/^/      /' "$COMP_ERR"
fi

# Edit 은 PreToolUse 에서 판정하지 않는다 — 조각만 오니까
printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/a.tsx","new_string":"x"}}' \
  "$TMP" "$TMP" | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/guard-components.sh" 2>/dev/null
if [ $? -eq 0 ]; then
  pass=$((pass + 1)); printf 'ok    %-32s Pre 에서 판정 안 함\n' 'Edit-guard-통과'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s\n' 'Edit-guard-통과'
fi

# PostToolUse 경고 — 완성된 파일을 읽는다
run_warn() {
  local fixture=$1 config=$2
  cp "$ROOT/fixtures/$fixture" "$TMP/a.tsx"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/a.tsx","new_string":"x"}}' \
    "$TMP" "$TMP" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/warn-components.sh" 2> "$COMP_ERR"
  warn_exit=$?
}

expect_warn() {
  local label=$1 want=$2 fixture=$3 config=${4:-}
  run_warn "$fixture" "$config"
  if [ "$warn_exit" -eq "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s exit=%s\n' "$label" "$warn_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s exit=%s (기대 %s)\n' "$label" "$warn_exit" "$want"
  fi
}

# exit 2 = 차단이 아니라 stderr 를 Claude 에게 보여주기
expect_warn 'Edit-2개-경고'        2 inline-two-components.tsx
expect_warn 'Edit-1개-무동작'      0 mixed-single-component.tsx
expect_warn 'disable.warn-무동작'  0 inline-two-components.tsx '{"disable":{"warn":true}}'

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
