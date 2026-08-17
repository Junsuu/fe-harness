#!/usr/bin/env bash
# fe-harness 설정 해석. docs/DESIGN.md 6장 「설정 파일 — 3단 폴백」.
#
#   1) 프로젝트 루트 .fe-harness.json 이 있으면 → 무조건 신뢰
#   2) 없으면 추론 (설정파일 존재 / node_modules 바이너리)
#   3) 추론도 실패하면 → 조용히 통과 (빈 문자열)
#
# 3번이 핵심이다. 하네스가 확신 없이 뭔가 실행해서 개발을 막는 것보다
# 아무것도 안 하는 게 낫다.
#
# set -e 를 쓰지 않는다 (7장). 실행 환경은 macOS 기본 bash 3.2.

# 프로젝트 루트. 훅 payload 의 .cwd 를 인자로 받는다.
fh_root() {
  local payload_cwd=${1:-}
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
  elif [ -n "$payload_cwd" ] && [ -d "$payload_cwd" ]; then
    printf '%s' "$payload_cwd"
  else
    printf '%s' "$PWD"
  fi
}

# .fe-harness.json 의 키를 읽는다. 없으면 빈 문자열.
# 사용: fh_cfg <root> <jq 경로>   예) fh_cfg "$root" '.format'
fh_cfg() {
  local root=$1 path=$2 file=$1/.fe-harness.json
  [ -f "$file" ] || return 0
  jq -r "$path // empty" "$file" 2>/dev/null
}

# 해당 훅이 꺼져 있는가. .fe-harness.json 의 disable.<name> 이 true 면 0(참).
# disable 을 반드시 넣는다 — 도구가 방해될 때 끌 방법이 없으면 사용자는 삭제한다.
fh_disabled() {
  local root=$1 name=$2
  [ "$(fh_cfg "$root" ".disable.$name")" = "true" ]
}

# 포맷 명령. 설정 → 추론 → 빈 문자열.
# 반환하는 명령은 대상 파일 경로 하나를 인자로 덧붙여 실행된다.
fh_format_cmd() {
  local root=$1 configured
  configured=$(fh_cfg "$root" '.format')
  if [ -n "$configured" ]; then
    printf '%s' "$configured"
    return 0
  fi

  # 설정 파일이 있는 포매터를 먼저 믿는다. 바이너리만 있는 건 그 다음.
  if _fh_has_biome_config "$root" && [ -x "$root/node_modules/.bin/biome" ]; then
    printf '%s' 'node_modules/.bin/biome format --write'
  elif _fh_has_prettier_config "$root" && [ -x "$root/node_modules/.bin/prettier" ]; then
    printf '%s' 'node_modules/.bin/prettier --write --ignore-unknown --log-level warn'
  elif [ -x "$root/node_modules/.bin/prettier" ]; then
    printf '%s' 'node_modules/.bin/prettier --write --ignore-unknown --log-level warn'
  elif [ -x "$root/node_modules/.bin/biome" ]; then
    printf '%s' 'node_modules/.bin/biome format --write'
  fi
  # 아무것도 못 찾으면 빈 문자열 — 조용히 통과
}

_fh_has_biome_config() {
  [ -f "$1/biome.json" ] || [ -f "$1/biome.jsonc" ]
}

_fh_has_prettier_config() {
  local root=$1 f
  for f in .prettierrc .prettierrc.json .prettierrc.yaml .prettierrc.yml \
           .prettierrc.json5 .prettierrc.js .prettierrc.cjs .prettierrc.mjs \
           prettier.config.js prettier.config.cjs prettier.config.mjs \
           .prettierrc.toml; do
    [ -f "$root/$f" ] && return 0
  done
  [ -f "$root/package.json" ] &&
    [ -n "$(jq -r '.prettier // empty' "$root/package.json" 2>/dev/null)" ]
}
