name: Watcher notifies and refuses dispatch when source recipe publication fails
command: |
  # Same harness as fixture 160: a COPY of scripts/ so watcher.sh (SCRIPT_DIR from $0)
  # calls a stub notify-escalation.sh that records its reason, with ROOT pinned at the
  # real tree so staging cp's resolve. The real run-cold-reviewer.sh runs; on a cursor
  # routing it plans and exits 2.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RD="$TMP/run"; SCR="$TMP/scripts"
  mkdir -p "$RD/checkpoints" "$SCR"
  cp "$ROOT/scripts/"*.py "$SCR/"
  cp "$ROOT/scripts/"*.sh "$SCR/" 2>/dev/null
  cp -R "$ROOT/scripts/lib" "$SCR/" 2>/dev/null || true
  # run-cold-reviewer.sh derives ROOT from its own location ($SCR/..), so give the
  # copied tree the real AGENTS.md, config/ and docs/ it binds against.
  cp "$ROOT/AGENTS.md" "$TMP/AGENTS.md"
  ln -s "$ROOT/agents" "$TMP/agents"
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

  mkdir "$RD/checkpoints/01-review-sources.json"
  FAILED="$RD/checkpoints/01.failed"
  RUN_DIR="$RD" ROOT="$ROOT" sh "$SCR/watcher.sh" "$RD" >"$TMP/watcher.out" 2>"$TMP/watcher.err" &
  WPID=$!
  i=0
  while [ ! -f "$FAILED" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.3
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

  set -e
  [ -f "$FAILED" ] || { cat "$TMP/watcher.err"; exit 1; }
  [ -f "$NOTED" ] && grep -q 'source recipe could not be written' "$NOTED"
  [ ! -d "$RD/checkpoints/01.lock" ]
  [ ! -e "$RD/checkpoints/01-1-1-reviewer-task-plan.json" ]
  [ ! -e "$RD/checkpoints/01-1-1-reviewer-verdict.json" ]
  echo PASS
expected: exit 0; notification names the failed recipe, checkpoint is poison-marked, lock released, no reviewer dispatched.
phase: reviewer staging
owner: scripts/watcher.sh
