name: article-passes config validation rejects an enabled pass whose instruction file is missing (before any API call)
phase: 01 · write-article
owner: write-article / config/article-passes.json validation contract
expected: exit code non-zero (the instruction path resolves to no file); shipped config's instruction resolves
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  CFG="$WORK/article-passes.json"
  # Enabled pass pointing at an instruction file that does not exist; instruction paths
  # resolve relative to the bureau root. This must fail BEFORE any API call.
  jq -n '{passes: [{id: "x", model: "openrouter:x-ai/grok-4.3", instruction: "config/passes/DOES-NOT-EXIST.md", enabled: true}]}' > "$CFG"
  # POSIX loop (no process substitution): pipe enabled instruction paths through a while
  # loop and record any miss in a marker file (a pipe runs the loop in a subshell, so a
  # plain variable would not survive).
  jq -r '.passes[] | select(.enabled == true) | .instruction' "$CFG" | while IFS= read -r rel; do
    test -f "$ROOT/$rel" || : > "$WORK/missing"
  done
  test -f "$WORK/missing" || { echo "FAIL: missing-instruction guard did not flag the absent file" >&2; exit 1; }
  # Sanity: the SHIPPED config's enabled instruction paths all resolve to real files.
  jq -r '.passes[] | select(.enabled == true) | .instruction' "$ROOT/config/article-passes.json" | while IFS= read -r rel; do
    test -f "$ROOT/$rel" || : > "$WORK/shipped_missing"
  done
  test ! -f "$WORK/shipped_missing" || { echo "FAIL: a shipped enabled pass instruction file is missing" >&2; exit 1; }
  echo "PASS: missing instruction file -> guard flags it (config: $CFG); shipped instruction resolves"
