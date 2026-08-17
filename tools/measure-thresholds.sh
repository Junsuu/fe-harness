#!/usr/bin/env bash
# 임계값의 진짜 비교 대상을 잰다.
#
#   maxNewFileLines → 파일이 **처음 만들어질 때**의 크기 (diff-filter=A)
#   maxEditLines    → **수정** 커밋에서 그 파일에 추가된 줄 수 (diff-filter=M)
#
# 현재 파일 크기를 쓰면 안 된다. 600줄 파일은 처음부터 600줄로 태어나지 않는다.
set -uo pipefail

SKIP='node_modules|/\.next/|/dist/|/build/|/\.turbo/|/coverage/|\.d\.ts$|/generated/|/__generated__/'

report() {
  local label=$1 limit=$2
  sort -n | awk -v L="$limit" -v LABEL="$label" '
    { v[NR] = $1; if ($1 > L) over++ }
    END {
      if (NR == 0) { printf "  %-14s (데이터 없음)\n", LABEL; exit }
      q50 = v[int(NR*0.50)]; q75 = v[int(NR*0.75)]; q90 = v[int(NR*0.90)]
      q95 = v[int(NR*0.95)]; q99 = v[int(NR*0.99)]
      printf "  %-14s n=%-6d p50=%-4d p75=%-4d p90=%-4d p95=%-4d p99=%-5d max=%-5d | %d줄 초과 %.1f%%\n",
        LABEL, NR, q50, q75, q90, q95, q99, v[NR], L, over*100/NR
    }'
}

collect() { # $1=repo $2=A|M
  git -C "$1" log --no-merges --diff-filter="$2" --numstat --pretty=format: \
    -- '*.ts' '*.tsx' 2>/dev/null \
    | awk 'NF == 3 && $1 != "-" { print $1 "\t" $3 }' \
    | grep -vE "$SKIP" \
    | awk -F'\t' '$1 > 0 { print $1 }'
}

for repo in "$@"; do
  [ -d "$repo" ] || continue
  printf '\n%s\n' "${repo##*/}"
  collect "$repo" A | report '생성시 크기' 250
  collect "$repo" M | report '수정시 추가' 150
done

printf '\n전체 합계\n'
for repo in "$@"; do collect "$repo" A; done | report '생성시 크기' 250
for repo in "$@"; do collect "$repo" M; done | report '수정시 추가' 150
