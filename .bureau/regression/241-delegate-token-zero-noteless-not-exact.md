name: account-tokens.sh — a present, final, note-free zero-processed DELEGATE leg is "suspect" (never "exact"), with a _note; absent block stays "unavailable", non-zero stays "exact" byte-clean
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  export BUREAU_POINTER_DIR="$TMPF/active-runs"; mkdir -p "$BUREAU_POINTER_DIR"

  # ── (a) THE WASH: drive the real conductor-stop.sh with a role:delegate pointer whose
  # baseline is null, firing ONCE with the run already closed (final:true). The baseline is
  # recorded on the SAME fire that emits, so delta = cumulative - baseline = 0 and no clamp
  # _note is written → a note-free zero-processed final DELEGATE-TOKEN-EVENT. Pre-fix this
  # rolled up to delegate_tokens {processed:0, confidence:"exact"} — byte-identical to the
  # confirmed 20260809-build-tail-tooling-fixes wash. Post-fix it must be "suspect" + _note.
  RUN_DIR="$TMPF/run"; mkdir -p "$RUN_DIR"; printf 'log\n' > "$RUN_DIR/log.md"
  printf '%s\n' '{"workflow":"feature","accounting":{"status":"complete"}}' > "$RUN_DIR/state.json"   # CLOSED → final:true
  printf '%s\n' '{"topology":"integrated","conductor_agent_id":"x"}' > "$RUN_DIR/delegate-state.json"
  KEY=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g'); PFILE="$BUREAU_POINTER_DIR/${KEY}.delegate"
  NONCE="del-nonce-241-$$"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-08-11T00:00:00Z","baseline":null,"project_dir":"","role":"delegate"}\n' \
    "$RUN_DIR" "$NONCE" > "$PFILE"                       # project_dir empty → Step C.0 legacy fall-through
  TX="$TMPF/tx.jsonl"
  printf '%s\n' \
    "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"RUN_DIR: $RUN_DIR nonce $NONCE\"}}" \
    '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5000,"cache_creation_input_tokens":100000,"cache_read_input_tokens":900000,"output_tokens":8000},"content":[{"type":"text","text":"w"}]}}' \
    > "$TX"
  printf '#!/bin/sh\nexit 0\n' > "$TMPF/noop.sh"; chmod +x "$TMPF/noop.sh"
  echo "{\"session_id\":\"del-sess-241\",\"transcript_path\":\"$TX\",\"stop_hook_active\":false}" \
    | BUREAU_ACCOUNT_RUN_SH="$TMPF/noop.sh" bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null

  # Confirm the emitted leg really is the note-free zero-with-final (the wash shape).
  dl=$(PATH=/usr/bin:$PATH grep '^DELEGATE-TOKEN-EVENT:' "$RUN_DIR/log.md" | head -1); dl="${dl#DELEGATE-TOKEN-EVENT: }"
  echo "$dl" | jq -e '.tokens.processed == 0 and .final == true and (has("_note") | not)' > /dev/null \
    || { echo "FAIL: expected a note-free zero-processed final delegate leg, got: $dl"; exit 1; }

  # The rollup must NOT be "exact"; it must be "suspect" WITH a _note naming the tell.
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN_DIR" 2>/dev/null)
  echo "$out" | jq -e '
    .delegate_tokens.tokens.processed == 0
    and .delegate_tokens.confidence == "suspect"
    and (.delegate_tokens.confidence != "exact")
    and (.delegate_tokens._note | test("processed==0"))
  ' > /dev/null || { echo "FAIL: zero delegate leg not degraded off exact: $(echo "$out" | jq -c .delegate_tokens)"; exit 1; }

  # ── (b) NO-REGRESSION — absent DELEGATE block stays "unavailable" (Facet B): the
  # gap-note path (integrated topology, zero DELEGATE lines) must be untouched.
  RPb="$TMPF/absent"; mkdir -p "$RPb"; echo '{"topology":"integrated"}' > "$RPb/delegate-state.json"; echo '{}' > "$RPb/state.json"
  printf '%s\n' 'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":0,"cache_read":0,"processed":100,"output":10},"final":true}' > "$RPb/log.md"
  bash "$ROOT/scripts/account-tokens.sh" "$RPb" 2>/dev/null | jq -e '.delegate_tokens.confidence == "unavailable" and .delegate_tokens.legs == 0' > /dev/null \
    || { echo "FAIL: absent delegate block no longer 'unavailable'"; exit 1; }

  # ── (c) NO-FALSE-FIRE — a legit non-zero final delegate leg stays "exact" with NO _note,
  # and the whole account-tokens output is byte-identical to the pre-fix (main) script on a
  # clean non-zero corpus (the strongest guard that the suspect rule is narrow).
  RPc="$TMPF/clean"; mkdir -p "$RPc"; echo '{}' > "$RPc/state.json"
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    > "$RPc/log.md"
  newc=$(bash "$ROOT/scripts/account-tokens.sh" "$RPc" 2>/dev/null)
  echo "$newc" | jq -e '.delegate_tokens.confidence == "exact" and (.delegate_tokens | has("_note") | not)' > /dev/null \
    || { echo "FAIL: clean non-zero delegate block perturbed"; exit 1; }
  git show main:scripts/account-tokens.sh > "$TMPF/old.sh"
  oldc=$(bash "$TMPF/old.sh" "$RPc" 2>/dev/null | jq -cS .)
  newc_sorted=$(echo "$newc" | jq -cS .)
  if [ "$oldc" != "$newc_sorted" ]; then
    echo "FAIL: output differs from pre-fix on a clean non-zero run"
    printf 'OLD: %s\n' "$oldc"
    printf 'NEW: %s\n' "$newc_sorted"
    exit 1
  fi

  echo "PASS"
  # Mutation note: revert the $del_zero_noteless_final branch in scripts/account-tokens.sh
  # (drop the "suspect" arm + its _note, letting a note-free zero take the exact bless) →
  # (a) regresses: the delegate rollup reads confidence:"exact" on the zero → RED. (b)/(c)
  # are no-regression guards (facet-B unavailable + clean-run byte-identity); they hold both
  # pre- and post-fix so they pin the narrowness of the suspect rule, not the mutation.
  #
  # Seam note: repro.md reserves NNN 236 for the DEFERRED Bug-1 token-capture fix (the
  # conductor-stop pointer-collision). This fixture (241) is the honesty slice only — it
  # asserts the zero is not labeled "exact", not that the real Delegate delta is recovered.
expected: exit 0; stdout "PASS"; a present final note-free zero-processed DELEGATE-TOKEN-EVENT leg rolls up to confidence "suspect" (never "exact") with a _note naming the tell; an absent delegate block stays "unavailable"; a clean non-zero delegate block stays "exact" with no _note and byte-identical to the pre-fix script.
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 1 honesty slice / scripts/account-tokens.sh delegate zero-noteless-final → suspect (capture fix deferred, seam 236)
