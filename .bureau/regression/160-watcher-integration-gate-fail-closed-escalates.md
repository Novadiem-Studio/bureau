name: #28 · watcher.sh CONSUMES integration-gate.sh exit code — a gate that fails closed (exit 2) makes the watcher ESCALATE (notify + NN.failed poison marker) and NOT spawn a reviewer on missing evidence
command: |
  # The watcher's integration path now captures the gate's exit code and, on a
  # non-zero exit, escalates instead of staging a reviewer against missing/partial
  # evidence. To force a deterministic gate `exit 2` inside the LIVE watcher flow
  # (no live `claude`), we run a COPY of scripts/ whose integration-gate.sh is a
  # stub that always exits 2. watcher.sh resolves SCRIPT_DIR from its own $0, so
  # the copied watcher calls the stub gate + the copied notify-escalation.sh; ROOT
  # is pointed back at the real tree so the pre-gate staging cp's still succeed.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RD="$TMP/run"; BIN="$TMP/bin"; SCR="$TMP/scripts"
  mkdir -p "$RD/checkpoints" "$BIN" "$SCR"

  # Copy the real scripts dir, then overwrite integration-gate.sh with a stub that
  # fails closed (exit 2, one stderr reason line — mirrors fixture 154's real gate
  # write-failure, but deterministically and without needing an unwritable dir).
  cp "$ROOT/scripts/"*.sh "$SCR/" 2>/dev/null
  cp -R "$ROOT/scripts/lib" "$SCR/" 2>/dev/null || true
  printf '#!/bin/sh\necho "integration-gate: --out dir is not writable: (stub fail-closed)" >&2\nexit 2\n' \
    > "$SCR/integration-gate.sh"
  chmod +x "$SCR/integration-gate.sh"

  # Stub notify-escalation.sh to RECORD its invocation ($3 = the reason) to a file.
  # The real one sends a macOS desktop notification when osascript is present and
  # therefore writes NO fallback file — so the fallback file is not a reliable
  # cross-platform signal. The stub captures the call deterministically.
  NOTED="$RD/checkpoints/notify.recorded"
  printf '#!/bin/sh\nprintf "%%s\\n" "$3" > "%s"\nexit 0\n' "$NOTED" > "$SCR/notify-escalation.sh"
  chmod +x "$SCR/notify-escalation.sh"

  # A `claude` stub on PATH: if the watcher were (wrongly) to reach the reviewer
  # spawn, it would run this and produce NN.delegate-out.json — the exact artifact
  # we assert is ABSENT. Its presence would prove a reviewer was spawned on missing
  # evidence (the bug).
  printf '#!/bin/sh\nprintf %s "{\\"decision\\":\\"proceed\\"}"\n' '' > "$BIN/claude"
  chmod +x "$BIN/claude"

  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' > "$RD/state.json"
  printf '# artifact under review\n' > "$RD/artifact.md"
  printf '# log slice\n' > "$RD/log-slice.md"
  HASH=$(shasum -a 256 "$RD/artifact.md" | awk '{print $1}')
  # integration request — REQ_CHECKPOINT_TYPE=integration drives the gate call
  {
    printf 'checkpoint: 01\n'
    printf 'run-dir: %s\n' "$RD"
    printf 'artifact: %s\n' "$RD/artifact.md"
    printf 'artifact-hash: %s\n' "$HASH"
    printf 'log-slice: %s\n' "$RD/log-slice.md"
    printf 'checkpoint-type: integration\n'
    printf 'worktree-path: (none)\n'
    printf 'base-ref: devel\n'
    printf 'claimed-gates: []\n'
  } > "$RD/checkpoints/01-request.md"

  FAILED="$RD/checkpoints/01.failed"
  OUTJSON="$RD/checkpoints/01.delegate-out.json"

  # Drive the LIVE watcher (copied tree → stub gate). ROOT pinned at the real tree
  # so pre-gate staging cp's resolve. Poll until the poison marker appears.
  PATH="$BIN:$PATH" RUN_DIR="$RD" ROOT="$ROOT" sh "$SCR/watcher.sh" "$RD" >/dev/null 2>&1 &
  WPID=$!
  i=0; while [ ! -f "$FAILED" ] && [ "$i" -lt 15 ]; do sleep 1; i=$((i+1)); done
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

  # (a) the poison marker was written (the checkpoint was given up on / escalated)
  [ -f "$FAILED" ] || { echo "FAIL: no NN.failed poison marker — watcher did not treat the gate fail-closed as a hard stop"; exit 1; }

  # (b) notify-escalation fired with a reason naming the gate fail-closed exit code
  # (captured by the stub, so this is deterministic on macOS and CI alike).
  [ -f "$NOTED" ] || { echo "FAIL: notify-escalation.sh was not invoked"; exit 1; }
  grep -q 'integration gate failed closed (exit 2)' "$NOTED" || { echo "FAIL: escalation reason does not name the gate fail-closed exit code"; cat "$NOTED"; exit 1; }

  # (c) NO reviewer was spawned on missing evidence — no NN.delegate-out.json.
  [ ! -f "$OUTJSON" ] || { echo "FAIL: a reviewer WAS spawned (NN.delegate-out.json exists) despite the gate failing closed"; exit 1; }

  echo "PASS"
  # Mutation note: remove the `gate_rc`/`if [ "$gate_rc" -ne 0 ]` escalate-and-return
  # block from scripts/watcher.sh (revert to ignoring the gate's exit code) and the
  # watcher falls through to stage + spawn the reviewer → 01.delegate-out.json is
  # written and 01.failed / ESCALATION-01.md are absent → all three asserts fail.
expected: exit 0; stdout "PASS"; on an integration request whose gate fails closed (exit 2), the watcher writes the NN.failed poison marker, fires notify-escalation.sh with a reason naming "integration gate failed closed (exit 2)", and does NOT spawn a reviewer (no NN.delegate-out.json). Mutation-test: deleting the gate_rc escalate-and-return block lets the watcher spawn a reviewer on missing evidence.
phase: 03 · execute-plan (Delegate v2) — audit follow-up #28
owner: scripts/watcher.sh integration-gate exit-code consumption (audit #28)
