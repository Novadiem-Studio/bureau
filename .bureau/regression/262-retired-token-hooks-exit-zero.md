name: FR4 REPLACE retired token hooks remain permanent fail-soft stubs
owner: scripts/conductor-stop.sh + scripts/subagent-stop.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RUN_PATH="$TMPF/run"
  NONCE="retired-hook-nonce"
  mkdir -p "$RUN_PATH"
  printf '%s\n' 'sentinel' > "$RUN_PATH/log.md"
  printf '%s\n' '{"accounting":{"status":"pending"}}' > "$RUN_PATH/state.json"
  jq -cn --arg run "$RUN_PATH" --arg nonce "$NONCE" \
    '{run_dir:$run,nonce:$nonce,written_at:"2026-08-13T00:00:00Z",project_dir:""}' \
    > "$TMPF/pointer"
  jq -cn --arg run "$RUN_PATH" --arg nonce "$NONCE" \
    '{type:"user",message:{role:"user",content:("RUN_DIR: "+$run+"\nRun nonce: "+$nonce)}}' \
    > "$TMPF/conductor.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"m-conductor","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/conductor.jsonl"
  conductor_out=$(printf '%s\n' "{\"session_id\":\"normal-fire\",\"transcript_path\":\"$TMPF/conductor.jsonl\"}" \
    | BUREAU_POINTER_FILE="$TMPF/pointer" bash "$ROOT/scripts/conductor-stop.sh" 2>"$TMPF/conductor.err")
  conductor_rc=$?
  [ "$conductor_rc" -eq 0 ] || { echo "FAIL: conductor-stop.sh exited $conductor_rc"; exit 1; }
  [ -z "$conductor_out" ] || { echo "FAIL: conductor-stop.sh emitted stdout: $conductor_out"; exit 1; }
  [ ! -s "$TMPF/conductor.err" ] || { echo "FAIL: conductor-stop.sh emitted stderr"; exit 1; }
  jq -cn --arg run "$RUN_PATH" --arg nonce "$NONCE" \
    '{type:"user",message:{role:"user",content:("RUN_DIR: "+$run+"\nAttempt ID: systemsmith-hook-fixture\nRun nonce: "+$nonce)}}' \
    > "$TMPF/agent-normal-fire.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"id":"m-specialist","usage":{"input_tokens":5,"cache_creation_input_tokens":6,"cache_read_input_tokens":7,"output_tokens":8},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/agent-normal-fire.jsonl"
  subagent_out=$(printf '%s\n' "{\"agent_id\":\"normal-fire\",\"agent_transcript_path\":\"$TMPF/agent-normal-fire.jsonl\"}" \
    | BUREAU_POINTER_FILE="$TMPF/pointer" bash "$ROOT/scripts/subagent-stop.sh" 2>"$TMPF/subagent.err")
  subagent_rc=$?
  [ "$subagent_rc" -eq 0 ] || { echo "FAIL: subagent-stop.sh exited $subagent_rc"; exit 1; }
  [ -z "$subagent_out" ] || { echo "FAIL: subagent-stop.sh emitted stdout: $subagent_out"; exit 1; }
  [ ! -s "$TMPF/subagent.err" ] || { echo "FAIL: subagent-stop.sh emitted stderr"; exit 1; }
  PATH=/usr/bin:$PATH grep -Eq '^(CONDUCTOR|DELEGATE|SPAWN)-TOKEN-EVENT:' "$RUN_PATH/log.md" \
    && { echo "FAIL: retired hook appended a token event"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; both still-wired retirement stubs return 0 and emit no token event
