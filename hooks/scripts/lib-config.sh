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

# 숫자 설정. 값이 없거나 숫자가 아니면 기본값.
# 사용: fh_cfg_num <root> <jq 경로> <기본값>
fh_cfg_num() {
  local root=$1 path=$2 default=$3 value
  value=$(fh_cfg "$root" "$path")
  case $value in
    '' | *[!0-9]*) printf '%s' "$default" ;;
    *) printf '%s' "$value" ;;
  esac
}

# 배열 설정을 줄 단위로. 없으면 아무것도 출력하지 않는다.
fh_cfg_list() {
  local root=$1 path=$2 file=$1/.fe-harness.json
  [ -f "$file" ] || return 0
  jq -r "$path[]? // empty" "$file" 2>/dev/null
}

# 해당 훅이 꺼져 있는가. .fe-harness.json 의 disable.<name> 이 true 면 0(참).
# disable 을 반드시 넣는다 — 도구가 방해될 때 끌 방법이 없으면 사용자는 삭제한다.
fh_disabled() {
  local root=$1 name=$2
  [ "$(fh_cfg "$root" ".disable.$name")" = "true" ]
}

# 게이트 대상 확장자인가. 기본값은 프론트엔드 소스 확장자.
#
# 문서·설정·스타일 파일을 분량으로 막지 않는다. 1장의 증상은 전부 컴포넌트
# 이야기이고, 긴 문서는 정상적으로 자주 쓴다 — 7장의 "정당하게 어겨야 하는
# 경우가 잦으면 막지 말 것" 기준에 걸린다.
fh_ext_allowed() {
  local root=$1 file=$2 ext=${2##*.} configured e
  [ "$ext" != "$file" ] || return 1  # 확장자 없음

  configured=$(fh_cfg_list "$root" '.extensions')
  if [ -z "$configured" ]; then
    configured='ts
tsx
js
jsx
mjs
cjs
vue
svelte'
  fi

  for e in $configured; do
    [ "$ext" = "$e" ] && return 0
  done
  return 1
}

# exclude 패턴에 걸리는가. 절대경로와 프로젝트 상대경로 둘 다 본다.
fh_excluded() {
  local root=$1 file=$2 rel=${2#"$1"/} pattern
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    _fh_glob_match "$pattern" "$rel" && return 0
    _fh_glob_match "$pattern" "$file" && return 0
  done <<EOF
$(fh_cfg_list "$root" '.exclude')
EOF
  return 1
}

# bash 3.2 의 case 패턴에는 ** 가 없다. case 의 * 는 / 도 매치하므로
# ** 를 * 로 낮추고, "**/" 접두사는 떼어낸 형태로도 한 번 더 본다
# (`**/*.test.tsx` 가 최상위의 `a.test.tsx` 에도 걸려야 한다).
_fh_glob_match() {
  local pattern=$1 path=$2 bare=${1#'**/'}
  pattern=${pattern//'**'/'*'}
  case $path in $pattern) return 0 ;; esac
  case $path in $bare) return 0 ;; esac
  return 1
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
