#!/bin/sh
# .bureau/regression/run.sh — run this repo's committed Bureau regression suite.
# Convention: docs/conventions/regression-fixtures.md § Regression fixture file format
# Promotion: scripts/promote-fixtures.sh reuses this runner for its post-copy green check.
#
# Resolves the repo root, exports $ROOT, and runs every NN-*.md fixture's
# `command:` field. A fixture PASSES when its command exits 0 (each fixture is
# authored so its guarantee holding == exit 0, and mutation-tested to exit
# non-zero when the guarantee is deleted). `retired:`/`slow:` fixtures are skipped.
#
# Usage:  sh .bureau/regression/run.sh
# Exit:   0 = all passed (or skipped), 1 = one or more failed, 2 = setup error.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)" || exit 2
export ROOT
cd "$ROOT" || exit 2
DIR="$ROOT/.bureau/regression"

pass=0; fail=0; skip=0; failed=""
for f in "$DIR"/[0-9][0-9]-*.md "$DIR"/[0-9][0-9][0-9]-*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  if grep -q '^retired:' "$f"; then echo "SKIP retired  $base"; skip=$((skip + 1)); continue; fi
  if grep -q '^slow:'    "$f"; then echo "SKIP slow     $base"; skip=$((skip + 1)); continue; fi
  # Extract the command: either a "command: |" indented block or an inline "command: ...".
  cmd=$(awk '
    /^command:[[:space:]]*\|[[:space:]]*$/ { blk = 1; next }
    blk == 1 {
      if ($0 ~ /^[[:space:]]/ || $0 == "") { sub(/^  /, ""); print; next }
      blk = 0
    }
    /^command:[[:space:]]*[^|]/ && got != 1 { sub(/^command:[[:space:]]*/, ""); print; got = 1 }
  ' "$f")
  if [ -z "$cmd" ]; then echo "FAIL no-cmd   $base"; fail=$((fail + 1)); failed="$failed $base"; continue; fi
  out=$(sh -c "$cmd" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS          $base"; pass=$((pass + 1))
  else
    echo "FAIL exit=$rc $base"; fail=$((fail + 1)); failed="$failed $base"
    echo "    last output: $(printf '%s' "$out" | tail -1)"
  fi
done
echo "---"
echo "pass=$pass fail=$fail skip=$skip  (root: $ROOT)"
[ -n "$failed" ] && { echo "FAILED:$failed"; exit 1; }
exit 0
