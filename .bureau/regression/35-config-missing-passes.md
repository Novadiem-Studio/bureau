name: article-passes config validation rejects valid JSON that lacks a passes array
phase: 01 · write-article
owner: write-article / config/article-passes.json validation contract
expected: exit code non-zero (the jq array-type guard fails when passes is absent); the file is named
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  CFG="$WORK/article-passes.json"
  # Valid JSON, but no `passes` array (a typo'd or wrong-shape config).
  jq -n '{notpasses: [{id: "grok"}]}' > "$CFG"
  set +e
  jq -e '.passes | type == "array"' "$CFG" >/dev/null 2>&1
  code=$?
  set -e
  test "$code" -ne 0 || { echo "FAIL: missing-passes guard returned 0" >&2; exit 1; }
  # Sanity: the SHIPPED config DOES have a passes array (guard returns 0 there).
  jq -e '.passes | type == "array"' "$ROOT/config/article-passes.json" >/dev/null \
    || { echo "FAIL: shipped config/article-passes.json has no passes array" >&2; exit 1; }
  echo "PASS: missing passes array -> guard nonzero (config: $CFG); shipped config has a passes array"
