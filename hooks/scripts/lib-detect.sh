#!/usr/bin/env bash
# fe-harness 탐지 primitive. 정규식 수정 시 test.sh 를 반드시 돌릴 것.
#
# 모든 함수는 stdin 으로 코드 본문을 받는다 — 임시파일 없음
# (BSD mktemp 호환 문제 회피).
#
# set -e 를 쓰지 않는다: 훅에서 exit 1 이 나가면 차단이 아니라
# non-blocking error 로 처리된다. docs/DESIGN.md 7장 참조.
#
# 실행 환경은 macOS 기본 bash 3.2 를 기준으로 한다 — bash 4 문법 금지.

# 컴포넌트 선언 개수
fh_count_components() {
  local body decl assign
  body=$(cat)
  decl=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?function[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*[(<]')
  assign=$(printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*(:[^=]*)?=[[:space:]]*(memo\b|forwardRef\b|function\b|\(|async[[:space:]]*\(|[a-z_$][A-Za-z0-9_$]*[[:space:]]*=>)' \
    | grep -cvE '=[[:space:]]*styled')
  echo $(( decl + assign ))
}

# Props 타입 내 boolean prop 이 THRESH 이상인 것 보고
fh_flag_props() {
  awk -v THRESH="${1:-2}" '
  function nm(s){ sub(/^[[:space:]]*(export[[:space:]]+)?(interface|type)[[:space:]]+/,"",s); sub(/[[:space:]]*[={].*$/,"",s); return s }
  /^[[:space:]]*(export[[:space:]]+)?(interface|type)[[:space:]]+[A-Za-z0-9_]*Props/ { inblk=1; name=nm($0); cnt=0; next }
  inblk && /^[[:space:]]*}/ { if (cnt>=THRESH) printf "%s (boolean prop %d개)\n", name, cnt; inblk=0; next }
  inblk && /^[[:space:]]*[A-Za-z0-9_]+\??[[:space:]]*:[[:space:]]*boolean[[:space:]]*;?[[:space:]]*$/ { cnt++ }
  '
}
