#!/usr/bin/env bash
# 저장소 사실 수집. /fe-harness:setup 이 설정을 만들 때 쓴다.
#
# 여기서 하는 것과 안 하는 것 (docs/DESIGN.md 「분류 축」의 분업을 그대로 따른다):
#   한다     "node_modules/.bin/knip 이 있나" 같은 **사실**
#   안 한다  "scripts.test 를 verify.test 에 넣어도 되나" 같은 **판단**
#
# 후자를 여기서 하면 안 된다. scripts.test 가 빠른 단위 테스트인지 몇 분짜리
# e2e 인지는 이름으로 알 수 없고, 잘못 넣으면 Stop 게이트가 매 턴 몇 분을 먹는다.
# 사실만 내고 판단은 커맨드를 읽는 모델과 사람이 한다.
#
# 출력은 JSON 한 덩어리. 실패해도 종료 코드는 0 이다.
#
# set -e 를 쓰지 않는다. macOS 기본 bash 3.2 기준.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib-config.sh
. "$SCRIPT_DIR/lib-config.sh"

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq 가 없습니다"}\n'; exit 0; }

root=$(fh_root "")
cd "$root" 2>/dev/null || { printf '{"error":"프로젝트 루트를 못 찾았습니다"}\n'; exit 0; }

PKG=$root/package.json

_first_existing() {
  local f
  for f in "$@"; do [ -e "$root/$f" ] && { printf '%s' "$f"; return 0; }; done
  return 1
}

# devDependencies · dependencies 어디에든 있으면 선언된 것으로 본다.
_declared() {
  [ -f "$PKG" ] || return 1
  [ -n "$(jq -r --arg n "$1" '((.dependencies // {}) + (.devDependencies // {}))[$n] // empty' "$PKG" 2>/dev/null)" ]
}

# 선언돼 있거나 바이너리가 실제로 있으면 쓸 수 있다.
_usable() {
  _declared "$1" && return 0
  [ -x "$root/node_modules/.bin/$1" ]
}

_bool() { if "$@"; then printf 'true'; else printf 'false'; fi; }

# ── 패키지 매니저 ───────────────────────────────────────────────────────
pm=""
[ -f "$PKG" ] && pm=$(jq -r '.packageManager // empty' "$PKG" 2>/dev/null | sed 's/@.*//')
if [ -z "$pm" ]; then
  if [ -f "$root/pnpm-lock.yaml" ]; then pm=pnpm
  elif [ -f "$root/yarn.lock" ]; then pm=yarn
  elif [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ]; then pm=bun
  elif [ -f "$root/package-lock.json" ]; then pm=npm
  fi
fi

# ── 린터 · 포매터 · 타입스크립트 ────────────────────────────────────────
eslint_cfg=$(_first_existing eslint.config.js eslint.config.mjs eslint.config.cjs \
  eslint.config.ts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json \
  .eslintrc.yml .eslintrc.yaml 2>/dev/null || printf '')
biome_cfg=$(_first_existing biome.json biome.jsonc 2>/dev/null || printf '')
prettier_cfg=$(_first_existing .prettierrc .prettierrc.json .prettierrc.js \
  .prettierrc.cjs .prettierrc.mjs .prettierrc.yaml .prettierrc.yml \
  prettier.config.js prettier.config.cjs prettier.config.mjs 2>/dev/null || printf '')
ts_cfg=$(_first_existing tsconfig.json 2>/dev/null || printf '')

# ── JSX 여부 ──────────────────────────────────────────────────────────
# a11y 정적 검사 제안은 JSX 가 있을 때만 의미가 있다.
jsx=false
if git -C "$root" ls-files '*.tsx' '*.jsx' 2>/dev/null | head -1 | grep -q .; then
  jsx=true
elif find "$root/src" -name '*.tsx' -o -name '*.jsx' 2>/dev/null | head -1 | grep -q .; then
  jsx=true
fi

# ── 렌더 수단 ─────────────────────────────────────────────────────────
# a11y 런타임 검사는 저장소가 이미 가진 수단에만 얹는다. 없으면 만들라고 하지 않는다.
storybook=$(_bool test -d "$root/.storybook")
playwright=$(_bool sh -c '[ -n "$(ls "'"$root"'"/playwright.config.* 2>/dev/null)" ]')
vitest=$(_bool sh -c '[ -n "$(ls "'"$root"'"/vitest.config.* 2>/dev/null)" ]')

# ── 모노레포 ──────────────────────────────────────────────────────────
# 루트에서 린터가 안 도는 저장소가 있다. 설정에 그 사실을 남겨야 한다.
monorepo=false
[ -f "$root/pnpm-workspace.yaml" ] && monorepo=true
[ -f "$PKG" ] && [ -n "$(jq -r '.workspaces // empty' "$PKG" 2>/dev/null)" ] && monorepo=true

scripts='{}'
[ -f "$PKG" ] && scripts=$(jq -c '.scripts // {}' "$PKG" 2>/dev/null || printf '{}')

jq -n \
  --arg pm "$pm" \
  --argjson hasPkg "$(_bool test -f "$PKG")" \
  --argjson scripts "$scripts" \
  --arg eslint "$eslint_cfg" \
  --arg biome "$biome_cfg" \
  --arg prettier "$prettier_cfg" \
  --arg tsconfig "$ts_cfg" \
  --argjson jsx "$jsx" \
  --argjson monorepo "$monorepo" \
  --argjson jscpd "$(_bool _usable jscpd)" \
  --argjson knip "$(_bool _usable knip)" \
  --argjson a11yPlugin "$(_bool _declared eslint-plugin-jsx-a11y)" \
  --argjson storybook "$storybook" \
  --argjson playwright "$playwright" \
  --argjson vitest "$vitest" \
  --argjson existingConfig "$(_bool test -f "$root/.fe-harness.json")" \
  '{
    packageManager: $pm,
    hasPackageJson: $hasPkg,
    scripts: $scripts,
    linter: (if $eslint != "" then "eslint" elif $biome != "" then "biome" else "" end),
    linterConfig: (if $eslint != "" then $eslint else $biome end),
    formatter: (if $prettier != "" then "prettier" elif $biome != "" then "biome" else "" end),
    typescript: ($tsconfig != ""),
    jsx: $jsx,
    monorepo: $monorepo,
    available: { jscpd: $jscpd, knip: $knip },
    a11yPlugin: $a11yPlugin,
    render: { storybook: $storybook, playwright: $playwright, vitest: $vitest },
    existingConfig: $existingConfig
  }'

exit 0
