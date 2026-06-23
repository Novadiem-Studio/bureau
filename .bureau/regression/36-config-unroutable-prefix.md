name: article-passes config validation rejects an enabled pass with an unroutable provider prefix
phase: 01 · write-article
owner: write-article / config/article-passes.json validation contract
expected: exit code non-zero (an enabled pass whose model lacks the openrouter: prefix fails the prefix check); shipped config passes
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  CFG="$WORK/article-passes.json"
  # An enabled pass routed to a provider with no v1 arm. Must fail loud, never silently skip.
  jq -n '{passes: [{id: "x", model: "direct:some-model", instruction: "config/passes/improve-grok.md", enabled: true}]}' > "$CFG"
  # The prefix guard the workflow mirrors: every ENABLED pass model must start with "openrouter:".
  set +e
  jq -e '[.passes[] | select(.enabled == true) | .model | startswith("openrouter:")] | all' "$CFG" >/dev/null 2>&1
  code=$?
  set -e
  test "$code" -ne 0 || { echo "FAIL: unroutable-prefix guard returned 0" >&2; exit 1; }
  # Sanity: the SHIPPED config's enabled passes all carry the openrouter: prefix (guard returns 0).
  jq -e '[.passes[] | select(.enabled == true) | .model | startswith("openrouter:")] | all' "$ROOT/config/article-passes.json" >/dev/null \
    || { echo "FAIL: a shipped enabled pass lacks the openrouter: prefix" >&2; exit 1; }
  echo "PASS: unroutable prefix -> guard nonzero (config: $CFG); shipped config all-openrouter"
