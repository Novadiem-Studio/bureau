name: F11 · watcher.sh routine path → live claude -p reviewer returns a valid verdict (no auth error) on current claude (AC7 routine path, --bare-drop proof)
slow: human judgment required
command: |
  # ── SEQUENCING (READ FIRST) ────────────────────────────────────────────────
  # RUN ONLY AFTER Prompt 5 writes the COLD-REVIEWER-MODE markers into
  # agents/delegate.md (the watcher stages the delegate-reviewer.md slice; an empty
  # slice gives the reviewer no persona). slow: this spawns a LIVE `claude -p`
  # (real spend, ~tens of seconds) and the verdict's substantive correctness is a
  # human judgment — carried as a Warning on re-run, never a Blocker. The objective
  # signal this fixture CHECKS is the one Phase-0 TEST 4/R6 made load-bearing: with
  # --bare DROPPED (kept --setting-sources "" + CWD=$CTX), the reviewer authenticates
  # and returns a decision rather than "Not logged in".
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RD="$TMP/run"; mkdir -p "$RD/checkpoints"
  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' > "$RD/state.json"
  printf '# artifact under review\n\nA tiny plan: add one function. No blockers.\n' > "$RD/artifact.md"
  printf '# log slice\n\nDesign agreed; nothing escalates.\n' > "$RD/log-slice.md"
  HASH=$(shasum -a 256 "$RD/artifact.md" | awk '{print $1}')
  # hand-crafted ROUTINE request (checkpoint-type: routine ⇒ no integration gate)
  {
    printf 'checkpoint: 01\n'
    printf 'run-dir: %s\n' "$RD"
    printf 'artifact: %s\n' "$RD/artifact.md"
    printf 'artifact-hash: %s\n' "$HASH"
    printf 'log-slice: %s\n' "$RD/log-slice.md"
    printf 'checkpoint-type: routine\n'
  } > "$RD/checkpoints/01-request.md"
  OUT="$RD/checkpoints/01.delegate-out.json"
  RUN_DIR="$RD" ROOT="$ROOT" sh "$ROOT/scripts/watcher.sh" "$RD" >/dev/null 2>&1 &
  WPID=$!
  i=0; while [ ! -s "$OUT" ] && [ "$i" -lt 120 ]; do sleep 2; i=$((i+1)); done
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
  [ -s "$OUT" ] || { echo "FAIL: reviewer produced no output (spawn never completed)"; exit 1; }
  if grep -Eiq 'not logged in|please run /login|invalid x-api-key|authentication' "$OUT"; then
    echo "FAIL: auth error in reviewer output (the --bare-drop fix regressed)"; cat "$OUT"; exit 1
  fi
  grep -Eiq 'proceed|revise|escalate' "$OUT" || { echo "FAIL: no decision token in reviewer output"; cat "$OUT"; exit 1; }
  echo "PASS (confirm the verdict is well-formed by inspection — human-judgment layer)"
expected: exit 0 — prints PASS: driving watcher.sh with a routine request spawns the live `claude -p` reviewer (CWD=$CTX, --setting-sources "", NO --bare) which authenticates cleanly (no "Not logged in" / login / api-key / authentication error in the output) and returns a decision token (proceed | revise | escalate). The human then confirms the verdict JSON is well-formed and on-checklist. Nonzero if the reviewer never completes, the output carries an auth error (the --bare-drop fix regressed), or no decision token is present.
phase: 2b · execute-plan (Bundle 15 P4) — RUN ONLY AFTER Prompt 5 (COLD-REVIEWER-MODE markers); slow (live claude -p) → Warning, not Blocker, on re-run
owner: prompts.md Prompt 4 (scripts/watcher.sh routine reviewer spawn)
