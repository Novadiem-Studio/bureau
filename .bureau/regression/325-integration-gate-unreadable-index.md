name: F325 · failure to read tracked fixtures records a blocking regression gate (PR #118 review)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; RUN="$TMP/run"; BIN="$TMP/bin"; OUT="$TMP/out"
  mkdir -p "$W/.bureau/regression" "$RUN/regression" "$BIN" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf 'base\n' > "$W/file"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf 'name: loose\n' > "$W/.bureau/regression/01-loose.md"
  printf '{"scope":{}}\n' > "$RUN/state.json"
  printf '#!/bin/sh\ntouch fallback-ran\n' > "$RUN/regression/run.sh"
  BUREAU_TEST_REAL_GIT=$(command -v git); export BUREAU_TEST_REAL_GIT
  cat > "$BIN/git" <<'EOF'
  #!/bin/sh
  for arg do
    if [ "$arg" = ls-files ]; then echo 'fatal: unreadable index' >&2; exit 128; fi
  done
  exec "$BUREAU_TEST_REAL_GIT" "$@"
  EOF
  chmod +x "$BIN/git"
  PATH="$BIN:$PATH" "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration --worktree-path "$W" \
    --base-ref "$BASE" --claimed-gates '[]' --known-flaky-gates '[{"name":"regression"}]' \
    --state-json "$RUN/state.json" --out "$OUT"
  jq -e '.gates | length==1' "$OUT/integration-results.json" >/dev/null
  jq -e '.gates[] | select(.name=="regression")
    | .result=="red" and .exit_code_branch==127 and .runner_source=="missing"
      and (.missing_reason|contains("could not inspect tracked regression fixtures"))
      and (has("flaky")|not)' "$OUT/integration-results.json" >/dev/null
  test ! -e "$W/fallback-ran"
  echo PASS
expected: exit 0; stdout "PASS". A git ls-files failure yields a red regression record with an inspection-failure reason, never an empty gate list or a flaky demotion, and does not execute the fallback. MUTATION - allowing the index-read exception to escape the canonical-gate generator yields an empty gate list and fails the count assertion.
phase: 117 · PR 118 review fixes
owner: scripts/integration-gate.sh (index read failure)
