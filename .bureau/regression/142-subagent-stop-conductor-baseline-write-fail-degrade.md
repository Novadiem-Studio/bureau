name: subagent-stop conductor baseline-write-fail — degrade to baseline-0 (raw cumulative), no crash, exit 0 (AC-7, EC-3 class)
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  touch "$RUN_PATH/log.md"
  echo '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"

  # Force the baseline write to fail on this first leg by pointing the store at a
  # path under a read-only directory (mktemp/mv both fail). The override env var
  # mirrors BUREAU_POINTER_FILE for the pointer store. macOS: chmod 0 on the
  # parent dir denies file creation inside it.
  RODIR="$TMPF/ro"
  mkdir -p "$RODIR"
  export BUREAU_SUBAGENT_BASELINE_FILE="$RODIR/.baseline.json"
  chmod 000 "$RODIR"

  jq -cn --arg rp "$RUN_PATH" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/t.jsonl"
  # Cumulative: input 100, cache_creation 200, cache_read 300, processed 600, output 10.
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/t.jsonl"

  echo '{"agent_transcript_path":"'"$TMPF/t.jsonl"'","agent_id":"agent-cond-142"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?
  # Restore perms so cleanup works regardless of outcome.
  chmod 755 "$RODIR" 2>/dev/null

  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }

  event=$(grep "^CONDUCTOR-TOKEN-EVENT:" "$RUN_PATH/log.md" | head -1)
  [ -n "$event" ] || { rm -rf "$TMPF"; exit 1; }
  payload="${event#CONDUCTOR-TOKEN-EVENT: }"
  # Write failed → baseline 0 this leg → emit the RAW cumulative (legacy 6-key
  # shape: no baseline key). processed == 600.
  echo "$payload" | jq -e '
    .tokens.processed == 600 and
    (has("baseline") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: make the write-back fatal (exit non-zero on write failure
  # instead of degrading) → the hook exits non-zero / emits nothing → the
  # event grep is empty → fixture fails. Proves the EC-3 honest-degrade path.
expected: exit 0; stdout "PASS"; on baseline-write failure the conductor branch degrades to baseline-0, emits the raw cumulative (processed=600) in the legacy 6-key shape (no baseline key), and still exits 0 with no crash
phase: 02 · feature
owner: subagent-stop.sh conductor baseline-write-fail degrade (v2-conductor-capture)
