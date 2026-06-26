name: F10 · watcher.sh → integration-gate.sh produces Track-3 PROCEED-EVIDENCE (AC7 integration path, field-for-field == F01 / pre-refactor)
slow: human judgment required
command: |
  # ── SEQUENCING (READ FIRST) ────────────────────────────────────────────────
  # RUN ONLY AFTER Prompt 5 writes the COLD-REVIEWER-MODE markers into
  # agents/delegate.md (the watcher stages the delegate-reviewer.md slice; an empty
  # slice means the reviewer has no persona). slow: this drives the LIVE watcher.sh
  # poll loop and spawns a reviewer — carried as a Warning on re-run, never a
  # Blocker. A `claude` STUB on PATH captures the staged evidence before teardown
  # (the watcher cd's into $CTX, so the stub copies integration-results.json from
  # its own CWD); the assertion mirrors fixture 03/F01 field-for-field.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RD="$TMP/run"; CAP="$TMP/cap"; BIN="$TMP/bin"; W="$TMP/wt"
  mkdir -p "$RD/checkpoints" "$CAP" "$BIN" "$W/.bureau/regression"
  # worktree: base commit (green regression runner + a flaky.txt), then 4 commits
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  printf 'broken\n' > "$W/flaky.txt"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  mkdir -p "$W/src"
  for i in 1 2 3 4; do echo "c$i" > "$W/src/f$i.txt"; git -C "$W" add -A; git -C "$W" commit -qm "c$i"; done
  # run state.json (scope projection the gate reads via --state-json)
  printf '{"scope":{"allowed_paths":["src/*",".bureau/*","flaky.txt"],"cut_symbols":[]}}\n' > "$RD/state.json"
  # staged read-set inputs the watcher requires to exist
  printf '# artifact under review\n' > "$RD/artifact.md"
  printf '# log slice\n' > "$RD/log-slice.md"
  HASH=$(shasum -a 256 "$RD/artifact.md" | awk '{print $1}')
  CLAIMED='[{"name":"regression","command":"sh '"$W"'/.bureau/regression/run.sh","result":"green","pre-existing":false},{"name":"unit","command":"test ! -f flaky.txt","result":"red","pre-existing":true}]'
  # hand-crafted integration request
  {
    printf 'checkpoint: 01\n'
    printf 'run-dir: %s\n' "$RD"
    printf 'artifact: %s\n' "$RD/artifact.md"
    printf 'artifact-hash: %s\n' "$HASH"
    printf 'log-slice: %s\n' "$RD/log-slice.md"
    printf 'checkpoint-type: integration\n'
    printf 'worktree-path: %s\n' "$W"
    printf 'base-ref: %s\n' "$BASE"
    printf 'claimed-gates: %s\n' "$CLAIMED"
  } > "$RD/checkpoints/01-request.md"
  # claude STUB: runs with CWD=$CTX, captures the staged evidence, emits a token verdict
  printf '#!/bin/sh\ncp integration-results.json "%s/" 2>/dev/null\nprintf '"'"'{"checkpoint":"01","decision":"proceed"}'"'"'\n' "$CAP" > "$BIN/claude"
  chmod +x "$BIN/claude"
  # drive the LIVE watcher for one poll cycle, then stop it
  PATH="$BIN:$PATH" RUN_DIR="$RD" ROOT="$ROOT" sh "$ROOT/scripts/watcher.sh" "$RD" >/dev/null 2>&1 &
  WPID=$!
  i=0; while [ ! -f "$CAP/integration-results.json" ] && [ "$i" -lt 15 ]; do sleep 1; i=$((i+1)); done
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
  [ -f "$CAP/integration-results.json" ] || { echo "FAIL: watcher did not stage integration-results.json via integration-gate.sh"; exit 1; }
  jq -e '.escalate_marker=="" and (.gates|length>0) and (all(.gates[];.result=="green")) and (.pre_existing|length>0) and (all(.pre_existing[];.confirmed_pre_existing==true)) and (.scope.scope_diff_clean==true) and (.scope.violations==[]) and (.fast_forward_ok==true) and (.conflicts_clean==true) and (has("verdict")|not)' "$CAP/integration-results.json" \
    && echo PASS
expected: exit 0 — prints PASS: the watcher.sh poll loop, on an integration request, calls integration-gate.sh which stages integration-results.json into $CTX carrying the Track-3 proceed-evidence fields field-for-field identical to fixture 03/F01 (escalate_marker=="" , every gates[].result=="green", every pre_existing[].confirmed_pre_existing==true, scope.scope_diff_clean==true, scope.violations==[], fast_forward_ok==true, conflicts_clean==true, and NO "verdict" key). Nonzero if the watcher→gate wiring fails to stage the file or any proceed-evidence field diverges from the pre-refactor watcher output.
phase: 2b · execute-plan (Bundle 15 P4) — RUN ONLY AFTER Prompt 5 (COLD-REVIEWER-MODE markers); slow (live watcher run) → Warning, not Blocker, on re-run
owner: prompts.md Prompt 4 (scripts/watcher.sh → scripts/integration-gate.sh)
