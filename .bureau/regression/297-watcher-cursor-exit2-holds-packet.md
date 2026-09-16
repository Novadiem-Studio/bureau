name: watcher treats run-cold-reviewer.sh exit 2 (Cursor host, Task required) as an attended hand-off — escalates once, poison-marks NN, releases the lock, keeps the staged packet and plan, runs no verdict-write and bumps no failcount
phase: multi-host Cursor adapter (issue #54)
owner: scripts/watcher.sh exit-2 branch; docs/host-cursor.md § The v1 watcher
command: |
  # Same harness as fixture 160: a COPY of scripts/ so watcher.sh (SCRIPT_DIR from $0)
  # calls a stub notify-escalation.sh that records its reason, with ROOT pinned at the
  # real tree so staging cp's resolve. The real run-cold-reviewer.sh runs; on a cursor
  # routing it plans and exits 2.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RD="$TMP/run"; SCR="$TMP/scripts"
  mkdir -p "$RD/checkpoints" "$SCR"
  cp "$ROOT/scripts/"*.sh "$SCR/" 2>/dev/null
  cp -R "$ROOT/scripts/lib" "$SCR/" 2>/dev/null || true
  # run-cold-reviewer.sh derives ROOT from its own location ($SCR/..), so give the
  # copied tree the real AGENTS.md, config/ and docs/ it binds against.
  ln -s "$ROOT/AGENTS.md" "$TMP/AGENTS.md"
  ln -s "$ROOT/config" "$TMP/config"
  ln -s "$ROOT/docs" "$TMP/docs"
  NOTED="$RD/checkpoints/notify.recorded"
  printf '#!/bin/sh\nprintf "%%s\\n" "$3" > "%s"\nexit 0\n' "$NOTED" > "$SCR/notify-escalation.sh"
  chmod +x "$SCR/notify-escalation.sh"

  printf '{"target_repo":"%s/target","scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' "$TMP" > "$RD/state.json"
  printf '{"runtime":"cursor","roles":{"delegate":{"model":"gpt-5.6-sol-medium"}}}\n' > "$RD/model-routing.json"
  printf '# artifact under review\n' > "$RD/artifact.md"
  printf '# log slice\n' > "$RD/log-slice.md"
  HASH=$(shasum -a 256 "$RD/artifact.md" | awk '{print $1}')
  cat > "$RD/checkpoints/01-request.md" <<REQ
  checkpoint: 01
  run-dir: $RD
  artifact: $RD/artifact.md
  artifact-hash: $HASH
  log-slice: $RD/log-slice.md
  checkpoint-type: routine
  revise-count: 0
  attempt: 1
  REQ

  FAILED="$RD/checkpoints/01.failed"
  RUN_DIR="$RD" ROOT="$ROOT" sh "$SCR/watcher.sh" "$RD" >"$TMP/watcher.out" 2>"$TMP/watcher.err" &
  WPID=$!
  i=0
  while [ ! -f "$FAILED" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.3
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

  [ -f "$FAILED" ] || { echo "FAIL: no 01.failed poison marker"; cat "$TMP/watcher.err"; exit 1; }
  grep -q 'giving up' "$TMP/watcher.err" && { echo "FAIL: watcher took the failed-spawn path instead of the hand-off"; cat "$TMP/watcher.err"; exit 1; }
  [ -f "$NOTED" ] && grep -q 'needs a host Task' "$NOTED" && grep -q -- '--resume' "$NOTED" \
    || { echo "FAIL: escalation not fired with the two-phase recovery"; cat "$NOTED" 2>/dev/null; exit 1; }
  [ -f "$RD/checkpoints/01-1-1-reviewer-task-plan.json" ] || { echo "FAIL: Task plan missing"; exit 1; }
  [ -d "$RD/checkpoints/01-context" ] && [ -f "$RD/checkpoints/01-context/artifact.sha256" ] \
    || { echo "FAIL: staged packet was torn down"; exit 1; }
  [ ! -e "$RD/checkpoints/01-verdict.md" ] || { echo "FAIL: a verdict was written without a reviewer"; exit 1; }
  [ ! -e "$RD/checkpoints/01.delegate-out.json" ] || { echo "FAIL: delegate-out written"; exit 1; }
  [ ! -e "$RD/checkpoints/01.failcount" ] || { echo "FAIL: failcount bumped for a host hand-off"; exit 1; }
  [ ! -d "$RD/checkpoints/01.lock" ] || { echo "FAIL: lock not released"; exit 1; }
  grep -q 'requires a host Task (exit 2)' "$TMP/watcher.err" || { echo "FAIL: watcher did not name the hand-off"; cat "$TMP/watcher.err"; exit 1; }
  grep -q 'cold-reviewer adapter failed' "$TMP/watcher.err" && { echo "FAIL: exit 2 reported as an adapter failure"; exit 1; }

  # the attended recovery completes the request: resume with a Task response, then verdict-write
  CTX="$RD/checkpoints/01-context"
  printf '{"Decision":"proceed","Artifact-hash":"%s","Uncertainties":"none","Rationale":"fixture","Required-changes":"none","Escalation":"none","Ledger":"fixture"}\n' "$HASH" > "$RD/checkpoints/01-1-1-reviewer-task-response.json"
  META=$(bash "$ROOT/scripts/run-cold-reviewer.sh" --resume "$RD/checkpoints/01-1-1-reviewer-task-response.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine 2>"$TMP/resume.err") \
    || { echo "FAIL: attended resume against the preserved packet failed"; cat "$TMP/resume.err"; exit 1; }
  VP=$(printf '%s' "$META" | jq -r .verdict_path)
  sh "$ROOT/scripts/verdict-write.sh" "$VP" "$RD/checkpoints/01-request.md" "$RD/checkpoints/01-verdict.md" "$RD/delegate-decisions.md" "$RD" 2 >/dev/null 2>"$TMP/vw.err" \
    || { echo "FAIL: verdict-write on the resumed verdict failed"; cat "$TMP/vw.err"; exit 1; }
  grep -Eq '^decision:[[:space:]]+proceed$' "$RD/checkpoints/01-verdict.md" || { echo "FAIL: bound verdict not written by the attended path"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". On a cursor routing the watcher's reviewer call exits 2; the watcher fires notify-escalation.sh with a reason naming the host Task and the --resume recovery, writes 01.failed, releases 01.lock, keeps 01-context (with artifact.sha256) and the Task plan, and writes no verdict, delegate-out, or failcount; it never logs "adapter failed". The attended path then resumes against the preserved packet and verdict-write.sh accepts the result. Mutation: delete the exit-2 branch in scripts/watcher.sh → verdict-write runs on a missing out.json, 01.failcount appears and 01-context is removed, so the packet and failcount asserts fail.
