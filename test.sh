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
expect_format '설정지정-실행' 1 '{"verify":{"format":"./fake-fmt.sh"}}'
# 끌 수 있어야 한다 — 끌 방법이 없으면 사용자는 플러그인을 삭제한다
expect_format 'disable.format-무동작' 0 '{"verify":{"format":"./fake-fmt.sh"},"disable":{"format":true}}'
# 프로젝트 밖의 파일은 건드리지 않는다
expect_format '프로젝트밖-무동작' 0 '{"verify":{"format":"./fake-fmt.sh"}}' "$TMP.outside.tsx"
rm -f "$TMP.outside.tsx"

# --- 분량 신호 -----------------------------------------------------------
# PostToolUse 라 차단이 아니다. exit 2 는 stderr 를 Claude 에게 보여주는 것.

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
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/warn-size.sh" 2> "$GUARD_ERR"
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
expect_guard 'Write-249줄-무동작'      0 Write "$TMP/a.tsx" 249
expect_guard 'Write-251줄-경고'      2 Write "$TMP/a.tsx" 251
expect_guard 'Edit-79줄-무동작'        0 Edit  "$TMP/a.tsx" 79
expect_guard 'Edit-81줄-경고'        2 Edit  "$TMP/a.tsx" 81

# 설정으로 조정된다
expect_guard '임계값설정-경고'        2 Write "$TMP/a.tsx" 60  '{"signals":{"maxNewFileLines":50}}'
expect_guard '임계값설정-무동작'        0 Write "$TMP/a.tsx" 40  '{"signals":{"maxNewFileLines":50}}'

# 끌 수 있어야 한다
expect_guard 'disable.signals-무동작'     0 Write "$TMP/a.tsx" 999 '{"disable":{"signals":true}}'

# 코드가 아닌 파일은 분량으로 막지 않는다 — 긴 문서는 정상이다
expect_guard '마크다운-무동작'          0 Write "$TMP/DESIGN.md" 999
expect_guard 'JSON-무동작'             0 Write "$TMP/data.json" 999

# exclude 패턴
expect_guard 'exclude-stories-무동작'   0 Write "$TMP/Button.stories.tsx" 999 \
  '{"exclude":["**/*.stories.tsx"]}'
expect_guard 'exclude-깊은경로-무동작'  0 Write "$TMP/src/gen/api.ts" 999 \
  '{"exclude":["src/gen/**"]}'
expect_guard 'exclude-비대상-경고'    2 Write "$TMP/src/app/api.ts" 999 \
  '{"exclude":["src/gen/**"]}'

# stderr 는 Claude 가 읽는다. "대신 무엇을 하라"가 반드시 들어가야 한다.
run_guard Write "$TMP/a.tsx" "$(nlines 300)" ''
if grep -q '별도 파일로 Write' "$GUARD_ERR" && grep -q '250줄' "$GUARD_ERR" &&
   grep -q '정당하게 긴 파일' "$GUARD_ERR" && ! grep -q 'disable' "$GUARD_ERR"; then
  pass=$((pass + 1))
  printf 'ok    %-32s 대안·예외안내 포함, 끄는법 미포함\n' 'stderr-문구'
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

# --- 컴포넌트 개수 — 신호 ------------------------------------------------
# 차단하지 않는다. PostToolUse(Write|Edit) 경고만. 판단은 review 역할이 한다.

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

# 완성된 파일을 읽어서 센다
run_warn() {
  local fixture=$1 config=$2 tool=${3:-Edit}
  cp "$ROOT/fixtures/$fixture" "$TMP/a.tsx"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s/a.tsx","new_string":"x"}}' \
    "${3:-Edit}" "$TMP" "$TMP" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/warn-components.sh" 2> "$COMP_ERR"
  warn_exit=$?
}

expect_warn() {
  local label=$1 want=$2 fixture=$3 config=${4:-} tool=${5:-Edit}
  run_warn "$fixture" "$config" "$tool"
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
expect_warn 'disable.signals-무동작' 0 inline-two-components.tsx '{"disable":{"signals":true}}'
# 옛 disable 키는 더 이상 안 먹는다 — 경고가 그대로 나야 한다
expect_warn 'disable.warn-구키워드무시' 2 inline-two-components.tsx '{"disable":{"warn":true}}'
# 차단 훅이 사라졌으므로 Write 도 여기서 신호를 내야 한다
expect_warn 'Write-2개-경고'       2 inline-two-components.tsx '' Write
expect_warn 'Write-1개-무동작'     0 mixed-single-component.tsx '' Write

# --- 린트 피드백 (P1-6) --------------------------------------------------
# 설정이 없으면 아무것도 안 한다. 있으면 남은 문제만 stderr 로 낸다.

LINT_ERR=$TMP/lint.stderr

run_lint() {
  local config=$1
  cp "$ROOT/fixtures/mixed-single-component.tsx" "$TMP/a.tsx"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/a.tsx"}}' "$TMP" "$TMP" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/lint-feedback.sh" 2> "$LINT_ERR"
  lint_exit=$?
}

expect_lint() {
  local label=$1 want=$2 config=$3
  run_lint "$config"
  if [ "$lint_exit" -eq "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s exit=%s\n' "$label" "$lint_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s exit=%s (기대 %s)\n' "$label" "$lint_exit" "$want"
    sed 's/^/      /' "$LINT_ERR"
  fi
}

# 린터 설정이 없는 프로젝트에서는 훅이 린터를 대신 만들어주지 않는다
expect_lint '린터없음-무동작'    0 ''
# 통과하는 린터
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/ok-lint.sh"; chmod +x "$TMP/ok-lint.sh"
expect_lint '린트통과-무동작'    0 '{"verify":{"lint":"./ok-lint.sh"}}'
# 실패하는 린터 → exit 2 로 Claude 에게 보여준다
printf '#!/usr/bin/env bash\necho "1:1 error no-unused-vars"\nexit 1\n' > "$TMP/ng-lint.sh"
chmod +x "$TMP/ng-lint.sh"
expect_lint '린트실패-피드백'    2 '{"verify":{"lint":"./ng-lint.sh"}}'
run_lint '{"verify":{"lint":"./ng-lint.sh"}}'
if grep -q 'no-unused-vars' "$LINT_ERR"; then
  pass=$((pass + 1)); printf 'ok    %-32s 린터 출력 전달됨\n' 'stderr-린터출력'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s\n' 'stderr-린터출력'
fi
expect_lint 'disable.lint-무동작' 0 '{"verify":{"lint":"./ng-lint.sh"},"disable":{"lint":true}}'

# 린터가 아예 못 돈 경우(설정·CLI 오류)를 코드 문제로 보고하면 안 된다.
# ESLint 는 1 이 lint 문제, 2 가 설정 오류다. 2026-08-18 현업 저장소에서
# 플래그 하나가 안 맞아 죽은 걸 "린트 문제" 로 보고한 적이 있다.
printf '#!/usr/bin/env bash\necho "Invalid option --nope"\nexit 2\n' > "$TMP/broken-lint.sh"
chmod +x "$TMP/broken-lint.sh"
expect_lint '린터실행실패-무동작' 0 '{"verify":{"lint":"./broken-lint.sh"}}'

# type-aware ESLint 가 tsconfig include 밖의 파일에 내는 에러도 코드 문제가 아니다
cat > "$TMP/tsconfig-lint.sh" <<'LINT'
#!/usr/bin/env bash
echo "  0:0  error  Parsing error: ESLint was configured to run on \`<tsconfigRootDir>/a.tsx\`"
echo "However, that TSConfig does not include this file."
exit 1
LINT
chmod +x "$TMP/tsconfig-lint.sh"
expect_lint 'tsconfig불일치-무동작' 0 '{"verify":{"lint":"./tsconfig-lint.sh"}}'

# --- 품질 게이트 (P1-4) --------------------------------------------------
# 제일 중요한 건 무한 루프 방지다.

GATE_ERR=$TMP/gate.stderr

run_gate() {
  local config=$1 active=${2:-false}
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf 'dirty\n' > "$TMP/dirty.txt"
  printf '{"hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "$TMP" "$active" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/gate-stop.sh" 2> "$GATE_ERR"
  gate_exit=$?
}

expect_gate() {
  local label=$1 want=$2 config=$3 active=${4:-false}
  run_gate "$config" "$active"
  if [ "$gate_exit" -eq "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-32s exit=%s\n' "$label" "$gate_exit"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-32s exit=%s (기대 %s)\n' "$label" "$gate_exit" "$want"
    sed 's/^/      /' "$GATE_ERR"
  fi
}

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/ok.sh"; chmod +x "$TMP/ok.sh"
printf '#!/usr/bin/env bash\necho "TS2304: Cannot find name"\nexit 2\n' > "$TMP/ng.sh"
chmod +x "$TMP/ng.sh"

# 설정이 없으면 절대 돌지 않는다 — 이 훅만은 추론하지 않는다
expect_gate '설정없음-무동작'      0 ''
expect_gate '타입체크통과-통과'    0 '{"verify":{"typecheck":"./ok.sh"}}'
expect_gate '타입체크실패-차단'    2 '{"verify":{"typecheck":"./ng.sh"}}'
expect_gate '테스트실패-차단'      2 '{"verify":{"test":"./ng.sh"}}'
expect_gate 'disable.gate-무동작'  0 '{"verify":{"typecheck":"./ng.sh"},"disable":{"gate":true}}'
# stop_hook_active 를 무시하면 무한 루프다
expect_gate '재진입-즉시통과'      0 '{"verify":{"typecheck":"./ng.sh"}}' true

run_gate '{"verify":{"typecheck":"./ng.sh"}}'
if grep -q 'TS2304' "$GATE_ERR" && grep -q '타입체크' "$GATE_ERR"; then
  pass=$((pass + 1)); printf 'ok    %-32s 실패 출력 전달됨\n' 'stderr-검사출력'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s\n' 'stderr-검사출력'
fi

# --- 규칙 주입 (P1-7) ----------------------------------------------------
# stdout 이 그대로 컨텍스트로 간다. 짧아야 하고, 실제 임계값을 말해야 한다.

run_inject() {
  local config=$1
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$TMP/.fe-harness.json"
  else
    rm -f "$TMP/.fe-harness.json"
  fi
  printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup"}' "$TMP" \
    | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/scripts/reinject.sh" 2>/dev/null
}

out=$(run_inject '')
if printf '%s' "$out" | grep -q '250줄' && printf '%s' "$out" | grep -q '80줄'; then
  pass=$((pass + 1)); printf 'ok    %-32s 실제 임계값 포함\n' '주입-기본문구'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-기본문구' "$out"
fi

# v2 에는 차단하는 훅이 없다. 막는다고 말하면 그게 거짓말이고 모델은 믿는다.
if printf '%s' "$out" | grep -qE '반려|차단은 하지' && printf '%s' "$out" | grep -q '신호'; then
  pass=$((pass + 1)); printf 'ok    %-32s 차단 아님을 명시\n' '주입-차단주장없음'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-차단주장없음' "$out"
fi

out=$(run_inject '{"signals":{"maxNewFileLines":120,"maxEditLines":40,"maxComponentsPerFile":3}}')
if printf '%s' "$out" | grep -q '120줄' && printf '%s' "$out" | grep -q '40줄' &&
   printf '%s' "$out" | grep -q '3개'; then
  pass=$((pass + 1)); printf 'ok    %-32s 설정을 반영\n' '주입-설정반영'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-설정반영' "$out"
fi

# 옛 평면 스키마를 읽지 않는 대신 반드시 알려야 한다 — 조용한 무시는 에러보다 나쁘다
out=$(run_inject '{"lint":"eslint","maxNewFileLines":120}')
if printf '%s' "$out" | grep -q '읽지 않습니다' && printf '%s' "$out" | grep -q 'lint' &&
   printf '%s' "$out" | grep -q 'maxNewFileLines'; then
  pass=$((pass + 1)); printf 'ok    %-32s 옛 키를 지목해서 알림\n' '주입-구스키마감지'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-구스키마감지' "$out"
fi

# 새 스키마만 있으면 마이그레이션 문구가 나오면 안 된다
out=$(run_inject '{"verify":{"lint":"eslint"},"signals":{"maxNewFileLines":120}}')
if printf '%s' "$out" | grep -q '읽지 않습니다'; then
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-신스키마오탐없음' "$out"
else
  pass=$((pass + 1)); printf 'ok    %-32s 오탐 없음\n' '주입-신스키마오탐없음'
fi

out=$(run_inject '{"inject":"우리 규칙 한 줄"}')
if [ "$out" = "우리 규칙 한 줄" ]; then
  pass=$((pass + 1)); printf 'ok    %-32s 사용자 문구로 대체\n' '주입-커스텀'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' '주입-커스텀' "$out"
fi

out=$(run_inject '{"disable":{"guide":true}}')
if [ -z "$out" ]; then
  pass=$((pass + 1)); printf 'ok    %-32s 아무것도 안 냄\n' 'disable.guide'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' 'disable.guide' "$out"
fi

# 주입 문구는 짧아야 한다. 여기 넣는 만큼 매 세션 컨텍스트를 먹는다.
lines=$(run_inject '' | wc -l | tr -d ' ')
if [ "$lines" -le 4 ]; then
  pass=$((pass + 1)); printf 'ok    %-32s %s줄 (상한 4)\n' '주입-분량' "$lines"
else
  fail=$((fail + 1)); printf 'FAIL  %-32s %s줄 — 길면 스킬로 가야 한다\n' '주입-분량' "$lines"
fi

# --- verify 확장 (중복·죽은 코드) ---------------------------------------
# 델타는 "이번 변경이 늘렸는가"만 본다. 못 재면 조용히 넘어간다 —
# 절대값은 행동으로 옮길 수 없어서 애초에 델타를 택했다.

VTMP=$TMP/verify-repo
mkdir -p "$VTMP"
(
  cd "$VTMP" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  cat > count.sh <<'CNT'
#!/usr/bin/env bash
printf '{"statistics":{"total":{"clones":%s}}}\n' "$(ls dup-*.txt 2>/dev/null | wc -l | tr -d ' ')"
CNT
  chmod +x count.sh
  touch dup-1.txt && git add -A && git commit -qm base
) >/dev/null 2>&1

vcfg() { printf '%s\n' "$1" > "$VTMP/.fe-harness.json"; }
vscan() { CLAUDE_PROJECT_DIR="$VTMP" bash "$ROOT/hooks/scripts/verify-scan.sh" "$@" 2>/dev/null; }

expect_scan() {
  local label=$1 want=$2 out
  shift 2
  out=$(vscan "$@")
  if { [ -n "$want" ] && printf '%s' "$out" | grep -q -- "$want"; } ||
     { [ -z "$want" ] && [ -z "$out" ]; }; then
    pass=$((pass + 1)); printf 'ok    %-32s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' "$label" "${out:-(빈 출력)}"
  fi
}

vcfg '{}'
expect_scan 'verify-설정없음-무동작'   '' delta

vcfg '{"verify":{"duplication":"./count.sh"}}'
# 첫 커밋이라 비교 대상이 없다 → 절대값을 대신 내면 안 된다
expect_scan 'verify-비교불가-조용'     '' delta

( cd "$VTMP" && touch dup-2.txt dup-3.txt && git add -A && git commit -qm more ) >/dev/null 2>&1
expect_scan 'verify-증가-보고'         '(+2)' delta
expect_scan 'verify-full-절대값'       '전체 3건' full

( cd "$VTMP" && git rm -q dup-2.txt dup-3.txt && git commit -qm less ) >/dev/null 2>&1
expect_scan 'verify-감소-보고'         '(-2)' delta

# 도구가 죽었을 때 0건으로 보고하면 그게 거짓말이다
vcfg '{"verify":{"duplication":"./nope.sh"}}'
expect_scan 'verify-도구실패-정직'     '재지 못했습니다' full

vcfg '{"verify":{"duplication":"./count.sh"},"disable":{"verify":true}}'
expect_scan 'disable.verify-무동작'    '' full

# --- learn (findings 누적 · 승격) ----------------------------------------
# 형식이 흔들리면 카운트가 깨지고, 카운트가 깨지면 루프가 닫히지 않는다.

FTMP=$TMP/findings-repo
mkdir -p "$FTMP"
( cd "$FTMP" && git init -q . && git config user.email t@t && git config user.name t \
  && touch x && git add -A && git commit -qm base ) >/dev/null 2>&1

fnd() { CLAUDE_PROJECT_DIR="$FTMP" bash "$ROOT/hooks/scripts/findings.sh" "$@" 2>&1; }

expect_fnd() {
  local label=$1 want=$2 out
  shift 2
  out=$(fnd "$@")
  if { [ -n "$want" ] && printf '%s' "$out" | grep -q -- "$want"; } ||
     { [ -z "$want" ] && [ -z "$out" ]; }; then
    pass=$((pass + 1)); printf 'ok    %-32s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  %-32s: %s\n' "$label" "${out:-(빈 출력)}"
  fi
}

# 카테고리를 고정하지 않으면 "같은 종류 3회"를 셀 수 없다
expect_fnd 'findings-잘못된카테고리'  '알 수 없는 카테고리' add nonsense "뭔가"

fnd add readability "중첩 삼항" src/A.tsx 반영 >/dev/null
fnd add readability "이름 불일치" src/B.tsx 미룸:범위밖 >/dev/null
expect_fnd 'findings-2회-조용'        '' count

fnd add readability "매직 넘버" src/C.tsx - >/dev/null
expect_fnd 'findings-3회-승격제안'    'readability — 3회' count
expect_fnd 'findings-승격경로안내'    'hookify' count

# 탭이 섞이면 필드가 밀린다
fnd add naming "탭	포함	요약" src/D.tsx - >/dev/null
n=$(fnd recent 20 | awk -F'\t' 'NF==7' | wc -l | tr -d ' ')
t=$(fnd recent 20 | wc -l | tr -d ' ')
if [ "$n" = "$t" ]; then
  pass=$((pass + 1)); printf 'ok    %-32s 전 줄 7칸 유지\n' 'findings-탭정규화'
else
  fail=$((fail + 1)); printf 'FAIL  %-32s %s/%s\n' 'findings-탭정규화' "$n" "$t"
fi

# 한 번 승격한 것을 계속 물으면 사용자는 끈다
sed -i '' 's/	-$/	승격:hookify/' "$FTMP/.fe-harness/findings.md" 2>/dev/null ||
  sed -i 's/\t-$/\t승격:hookify/' "$FTMP/.fe-harness/findings.md"
expect_fnd 'findings-승격후-재제안없음' '' count

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
