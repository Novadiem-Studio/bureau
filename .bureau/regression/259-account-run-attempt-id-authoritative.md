name: account-run attempt-id authoritative — null agent replaces stale live tokens, unequal non-null agents surface suspect, and unattributed post-hoc cost is surfaced once
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT

  # Case 1: the attempt exists in live accounting, but no transcript candidate
  # resolves. Null post-hoc agent_id must not block authoritative unavailable.
  TARGET1="$TMPF/null-target"
  RP1="$TARGET1/.bureau/runs/20260813-null-agent"
  PROJECTS1="$TMPF/null-projects"
  SID1="delegate-null"
  M1=$(printf '%s' "$TARGET1" | sed 's#[/.]#-#g')
  mkdir -p "$RP1" "$PROJECTS1/$M1/$SID1/subagents"
  printf '{"runtime":"claude"}\n' > "$RP1/model-routing.json"
  jq -cn --arg target "$TARGET1" '{target_repo:$target,workflow:"feature",phase_status:"complete",phases_complete:["analyst"],critic_loops:{}}' > "$RP1/state.json"
  jq -cn --arg sid "$SID1" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:00Z"}' > "$RP1/delegate-state.json"
  jq -cn --arg run "$RP1" '{run_dir:$run,nonce:"nonce-null",written_at:"2026-08-12T23:59:59Z"}' > "$TMPF/null-pointer"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-08-13T00:00:02Z","started_at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"old-live-agent","turns":4,"tokens":{"input":999,"cache_creation":0,"cache_read":0,"processed":999,"output":99}}' \
    > "$RP1/log.md"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"delegate-null-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[]}}' > "$PROJECTS1/$M1/$SID1.jsonl"

  BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS1" BUREAU_POINTER_FILE="$TMPF/null-pointer" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
    bash "$ROOT/scripts/account-run.sh" "$RP1" >/dev/null 2>&1 || exit 1
  jq -e '
    .specialist_spawns[0].tokens.processed == {value:0,confidence:"unavailable"} and
    .specialist_spawns[0].turns == {value:0,confidence:"unavailable"} and
    .specialist_spawns[0].confidence == "unavailable" and
    (.specialist_spawns[0]._note | contains("no run-scoped transcript resolved")) and
    (.specialist_spawns[0]._note | contains("agent mismatch") | not)
  ' "$RP1/accounting.json" >/dev/null || exit 1

  # Case 2: attempt_id matches, but both agent ids are present and unequal. The
  # post-hoc figure still replaces live cost, carrying a suspect disposition.
  TARGET2="$TMPF/mismatch-target"
  RP2="$TARGET2/.bureau/runs/20260813-mismatch"
  PROJECTS2="$TMPF/mismatch-projects"
  SID2="delegate-mismatch"
  M2=$(printf '%s' "$TARGET2" | sed 's#[/.]#-#g')
  SESSION2="$PROJECTS2/$M2/$SID2"
  mkdir -p "$RP2" "$SESSION2/subagents"
  printf '{"runtime":"claude"}\n' > "$RP2/model-routing.json"
  jq -cn --arg target "$TARGET2" '{target_repo:$target,workflow:"feature",phase_status:"complete",phases_complete:["analyst"],critic_loops:{}}' > "$RP2/state.json"
  jq -cn --arg sid "$SID2" '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:00Z"}' > "$RP2/delegate-state.json"
  jq -cn --arg run "$RP2" '{run_dir:$run,nonce:"nonce-mismatch",written_at:"2026-08-12T23:59:59Z"}' > "$TMPF/mismatch-pointer"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-08-13T00:00:02Z","started_at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"old-live-agent","turns":4,"tokens":{"input":999,"cache_creation":0,"cache_read":0,"processed":999,"output":99}}' \
    > "$RP2/log.md"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"delegate-mismatch-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[]}}' > "$SESSION2.jsonl"
  jq -cn --arg run "$RP2" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: nonce-mismatch\n")}}' > "$SESSION2/subagents/agent-new-posthoc-agent.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"matched-cost","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":4},"content":[]}}' >> "$SESSION2/subagents/agent-new-posthoc-agent.jsonl"
  # A run-scoped transcript with no Attempt ID becomes one null-attempt,
  # unattributed post-hoc row. It must be counted and surfaced exactly once.
  jq -cn --arg run "$RP2" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nRun nonce: nonce-mismatch\n")}}' > "$SESSION2/subagents/agent-unattributed-one.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"unattributed-cost","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4,"output_tokens":1},"content":[]}}' >> "$SESSION2/subagents/agent-unattributed-one.jsonl"

  BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS2" BUREAU_POINTER_FILE="$TMPF/mismatch-pointer" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
    bash "$ROOT/scripts/account-run.sh" "$RP2" >/dev/null 2>&1 || exit 1
  jq -e '
    .specialist_spawns[0].tokens.processed == {value:60,confidence:"suspect"} and
    .specialist_spawns[0].confidence == "suspect" and
    (.specialist_spawns[0]._note | contains("old-live-agent != transcript new-posthoc-agent")) and
    (.tokens.unattributed_records | length) == 1 and
    .tokens.unattributed_records[0].attempt_id == null and
    .tokens.unattributed_records[0].agent_id == "unattributed-one" and
    .tokens.unattributed_records[0].tokens.processed == 9
  ' "$RP2/accounting.json" >/dev/null || exit 1
  echo "PASS"
  # Mutation: match on agent_id instead of required attempt_id, or require a
  # non-null post-hoc agent_id, and Case 1 retains stale 999. Remove the mismatch
  # guard and Case 2 is silently exact. Drop null-attempt surfacing and its length
  # assertion fails.
expected: exit 0; stdout "PASS"; null post-hoc agent replaces stale live 999 with unavailable zero/note, unequal non-null agent ids replace with post-hoc 60 marked suspect, and one null-attempt transcript is surfaced once with processed 9
phase: 04 · execute-plan
owner: Prompt 04 / account-run.sh attempt-id authoritative specialist replacement
