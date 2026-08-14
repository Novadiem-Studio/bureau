name: BUREAU_ACCOUNT_RUN_SH — forced shim failure: ordering proven via sentinel, pointer temporal removal, exit 0 (AC 5, FR 8)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  export BUREAU_POINTER_FILE="$TMPF/ptr"
  SHIM_DIR="$TMPF/shim"
  mkdir -p "$SHIM_DIR"
  printf '#!/usr/bin/env bash\ngrep -c '"'"'"final":true'"'"' "$1/log.md" > "%s/final-at-shim"\n[ -f "$BUREAU_POINTER_FILE" ] && echo yes > "%s/ptr-at-shim" || echo no > "%s/ptr-at-shim"\nexit 1\n' "$TMPF" "$TMPF" "$TMPF" > "$SHIM_DIR/account-run.sh"
  chmod +x "$SHIM_DIR/account-run.sh"
  export BUREAU_ACCOUNT_RUN_SH="$SHIM_DIR/account-run.sh"
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_PATH/state.json"
  NONCE="nonce-fixture-f-case7"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-01-01T00:00:00Z","baseline":null}\n' "$RUN_PATH" "$NONCE" > "$BUREAU_POINTER_FILE"
  printf '%s\n' "RUN_DIR: $RUN_PATH" "NONCE: $NONCE" > "$TMPF/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"msg-F","usage":{"input_tokens":5000000,"cache_creation_input_tokens":2000000,"cache_read_input_tokens":1000000,"output_tokens":100000},"content":[{"type":"text"}]}}' >> "$TMPF/t.jsonl"
  echo '{"session_id":"sess-F","transcript_path":"'"$TMPF/t.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  cnt=$(cat "$TMPF/final-at-shim" 2>/dev/null)
  [ "${cnt:-0}" -ge 1 ] || { rm -rf "$TMPF"; exit 1; }
  ptr_at_shim=$(cat "$TMPF/ptr-at-shim" 2>/dev/null)
  [ "$ptr_at_shim" = "yes" ] || { rm -rf "$TMPF"; exit 1; }
  [ ! -e "$BUREAU_POINTER_FILE" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; (1) ORDERING PROVEN: final-at-shim count >= 1 — "final":true already in log.md when shim ran (Step F before Step G(2)); moving Step F append to after G(2) shim call yields final-at-shim=0 and fixture exits non-zero; (2) TEMPORAL REMOVAL: ptr-at-shim is "yes" (pointer existed at shim invocation) AND pointer absent after hook exits (Step G(3) ran after shim exit-1); (3) hook exits 0 (non-zero shim result captured by if/else/fi, not propagated). Mutation guard: replace if/else/fi wrapper with unconditional call + exit $? -> hook exits 1 -> rc check fails -> fixture exits non-zero.
phase: 05 · feature (execute build tail)
owner: prompts.md § Prompt 5 — Fixture F, BUREAU_ACCOUNT_RUN_SH forced shim failure (AC 5, FR 8, FR 9)
