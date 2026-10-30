name: A failed scope diff blocks verification while absent scope stays neutral (issue 89)
command: |
  set -eu
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/work"; OUT="$TMP/out"
  mkdir -p "$W/.bureau/regression" "$OUT" "$TMP/bin"
  git -C "$W" init -q
  git -C "$W" config user.name fixture
  git -C "$W" config user.email fixture@example.test
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  printf 'before\n' > "$W/file.txt"
  git -C "$W" add .; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf 'after\n' > "$W/file.txt"
  git -C "$W" commit -qam change
  HEAD_SHA=$(git -C "$W" rev-parse HEAD)
  REAL_GIT=$(command -v git); export REAL_GIT
  cat > "$TMP/bin/git" <<'SH'
  #!/bin/sh
  for arg do
    if [ "$arg" = "${FAIL_SCOPE_ARG:-never}" ]; then
      echo 'injected scope git failure' >&2
      exit 42
    fi
  done
  exec "$REAL_GIT" "$@"
  SH
  chmod +x "$TMP/bin/git"
  PATH="$TMP/bin:$PATH"; export PATH
  run_gate() {
    sh "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration \
      --worktree-path "$W" --base-ref "$1" --claimed-gates '[]' \
      --state-json "$TMP/state.json" --final --out "$OUT" >/dev/null
  }
  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' > "$TMP/state.json"
  # The early invalid-base guard must expose the unverified scope too.
  run_gate missing-ref
  jq -e '.scope.scope_diff_clean == false and (.scope.scope_error | length > 0) and .escalate_marker != ""' "$OUT/integration-results.json"
  # A valid base passes preflight; failures during each diff query must still block.
  for FAIL_SCOPE_ARG in --name-only --numstat --no-color; do
    export FAIL_SCOPE_ARG
    run_gate "$BASE"
    jq -e '.scope.scope_diff_clean == false and (.scope.scope_error | contains("git diff"))' "$OUT/integration-results.json"
  done
  # Terminal pairing must not call this otherwise-green final gate green.
  set +e
  sh "$ROOT/scripts/terminal-pairing.sh" --gate "$OUT/integration-results.json" --review-sha "$HEAD_SHA" > "$TMP/pair.json"
  RC=$?
  set -e
  [ "$RC" -eq 1 ]
  jq -e '.paired == false and (.reason | contains("scope verification"))' "$TMP/pair.json"
  # No scope declared: even an injected diff failure is irrelevant and neutral.
  printf '{}\n' > "$TMP/state.json"
  run_gate "$BASE"
  jq -e '.scope.scope_diff_clean == null and (.scope | has("scope_error") | not)' "$OUT/integration-results.json"
  unset FAIL_SCOPE_ARG
  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' > "$TMP/state.json"
  run_gate "$BASE"
  jq -e '.scope.scope_diff_clean == true and (.scope | has("scope_error") | not)' "$OUT/integration-results.json"
  sh "$ROOT/scripts/terminal-pairing.sh" --gate "$OUT/integration-results.json" --review-sha "$HEAD_SHA" >/dev/null
  # Unreadable/malformed supplied state is not evidence that scope was absent.
  printf '{broken\n' > "$TMP/state.json"
  run_gate "$BASE"
  jq -e '.scope.scope_diff_clean == false and (.scope.scope_error | length > 0)' "$OUT/integration-results.json"
  rm "$TMP/state.json"
  run_gate "$BASE"
  jq -e '.scope.scope_diff_clean == false and (.scope.scope_error | length > 0)' "$OUT/integration-results.json"
  printf '{"scope":{"allowed_paths":"**"}}\n' > "$TMP/state.json"
  run_gate "$BASE"
  jq -e '.scope.scope_diff_clean == false and (.scope.scope_error | contains("array of strings"))' "$OUT/integration-results.json"
  printf 'PASS\n'
expected: exit 0; scope errors block, absent scope remains neutral, successful scope remains green, terminal pairing refuses scope errors.
phase: integration verification
owner: scripts/integration-gate.sh + scripts/terminal-pairing.sh
