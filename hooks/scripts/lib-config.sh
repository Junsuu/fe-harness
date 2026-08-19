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
# 사용: fh_cfg <root> <jq 경로>   예) fh_cfg "$root" '.verify.lint'
#
# 0.1.x 평면 스키마는 읽지 않는다. 대신 fh_legacy_keys 가 감지해서 알린다 —
# 폴백을 영구히 들고 다니는 것보다 한 번 옮기게 하는 쪽이 낫다.
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

# 0.1.x 평면 스키마 키가 남아 있으면 그 이름들을 출력한다. 없으면 아무것도.
#
# 스키마를 verify.* / signals.* 로 묶으면서 옛 키는 읽지 않기로 했다.
# 그런데 **설정이 조용히 무시되는 것은 에러보다 나쁘다** — 사용자는 자기 설정이
# 도는 줄 안다. 읽지 않을 거라면 읽지 않는다고 말해야 한다.
fh_legacy_keys() {
  local file=$1/.fe-harness.json
  [ -f "$file" ] || return 0
  jq -r '
    [ "format","lint","typecheck","test",
      "maxNewFileLines","maxEditLines","maxComponentsPerFile" ]
    | map(select(. as $k | $ARGS.named.cfg | has($k)))
    | join(", ")
  ' --argjson cfg "$(cat "$file")" -n 2>/dev/null
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

# 파일이 속한 가장 가까운 패키지 디렉터리. 없으면 root.
#
# 모노레포에서 필요하다 (2026-08-18 실측). 루트 .eslintrc.js 가
# `@repo/eslint-config` 같은 워크스페이스 패키지를 참조하면 루트에서는
# 해석이 안 돼서 린터가 아예 못 돈다. 파일이 속한 패키지에서 돌려야 한다.
fh_package_dir() {
  local root=$1 dir
  dir=$(dirname "$2")
  while [ "$dir" != "$root" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/package.json" ]; then
      printf '%s' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  printf '%s' "$root"
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
  configured=$(fh_cfg "$root" '.verify.format')
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

# 린트 명령. 설정 → 추론 → 빈 문자열.
# 반환하는 명령은 대상 파일 경로 하나를 인자로 덧붙여 실행된다.
#
# 포맷과 달리 --fix 를 붙인다. 고칠 수 있는 건 조용히 고치고,
# 남은 것만 Claude 에게 보여주는 게 목적이다.
fh_lint_cmd() {
  local root=$1 configured
  configured=$(fh_cfg "$root" '.verify.lint')
  if [ -n "$configured" ]; then
    printf '%s' "$configured"
    return 0
  fi

  # 플래그를 최소한만 쓴다. --no-warn-ignored 는 ESLint 9 flat config 전용이라
  # eslintrc 를 쓰는 저장소에서 "Invalid option" 으로 죽는다 (2026-08-18 실측).
  # 버전마다 있는 플래그를 고르느니 아무것도 안 붙이는 쪽이 안전하다.
  # 추론한 명령은 패키지 디렉터리에서 실행되므로 바이너리를 절대경로로 낸다.
  if _fh_has_eslint_config "$root" && [ -x "$root/node_modules/.bin/eslint" ]; then
    printf '%s' "$root/node_modules/.bin/eslint --fix"
  elif _fh_has_biome_config "$root" && [ -x "$root/node_modules/.bin/biome" ]; then
    printf '%s' "$root/node_modules/.bin/biome check --write"
  fi
  # 설정 파일이 없으면 추론하지 않는다. 린터 설정이 없는 프로젝트에서
  # 훅이 린터를 대신 만들어줄 수는 없다.
}

_fh_has_eslint_config() {
  local root=$1 f
  for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
           .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
    [ -f "$root/$f" ] && return 0
  done
  [ -f "$root/package.json" ] &&
    [ -n "$(jq -r '.eslintConfig // empty' "$root/package.json" 2>/dev/null)" ]
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
