name: account-run post-hoc W4 — unchanged close-out is byte-identical, resumed run growth re-bounds and accounts a post-close-out specialist
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT
  TARGET="$TMPF/target"
  RP="$TARGET/.bureau/runs/20260813-idempotent-growth"
  PROJECTS="$TMPF/projects"
  SID="delegate-idempotent"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g')
  SESSION="$PROJECTS/$M/$SID"
  mkdir -p "$RP" "$SESSION/subagents"
  printf '{"runtime":"claude"}\n' > "$RP/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target,workflow:"feature",phase_status:"complete",phases_complete:["analyst"],critic_loops:{analyst:1}}' > "$RP/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"cond-idem",conductor_agent_ids:["cond-idem"],run_started_at:"2026-08-13T00:00:00Z"}' > "$RP/delegate-state.json"
  jq -cn --arg run "$RP" '{run_dir:$run,nonce:"nonce-idem",written_at:"2026-08-12T23:59:59Z"}' > "$TMPF/pointer"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-08-13T00:00:02Z","started_at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"analyst-idem","tokens":{"input":999,"cache_creation":0,"cache_read":0,"processed":999,"output":9}}' \
    > "$RP/log.md"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"delegate-idem-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4},"content":[]}}' > "$SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"cond-idem-turn","usage":{"input_tokens":4,"cache_creation_input_tokens":5,"cache_read_input_tokens":6,"output_tokens":7},"content":[]}}' > "$SESSION/subagents/agent-cond-idem.jsonl"
  jq -cn --arg run "$RP" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: nonce-idem\n")}}' > "$SESSION/subagents/agent-analyst-idem.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"analyst-idem-turn","usage":{"input_tokens":7,"cache_creation_input_tokens":8,"cache_read_input_tokens":9,"output_tokens":10},"content":[]}}' >> "$SESSION/subagents/agent-analyst-idem.jsonl"

  run_accounting() {
    BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
      bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  }
  run_accounting || exit 1
  cp "$RP/accounting.json" "$TMPF/first.json"
  FIRST_BOUND=$(jq -r '._posthoc.run_ended_at' "$TMPF/first.json")
  sleep 2
  run_accounting || exit 1
  cmp -s "$TMPF/first.json" "$RP/accounting.json" || exit 1
  [ "$(jq -r '._posthoc.run_ended_at' "$RP/accounting.json")" = "$FIRST_BOUND" ] || exit 1

  # Grow the immutable run-state basis by one exact SPAWN-EVENT line. Its usage
  # timestamp is after the first bound, so incorrectly reusing that frozen bound
  # produces a clean-labelled zero and the processed=18 assertion catches it.
  NEW_TS=$(jq -nr --arg t "$FIRST_BOUND" '$t | fromdateiso8601 | . + 1 | todateiso8601')
  printf 'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"architect-1","status":"started","at":"%s"}\n' "$NEW_TS" >> "$RP/log.md"
  jq -cn --arg run "$RP" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: architect-1\nRun nonce: nonce-idem\n")}}' > "$SESSION/subagents/agent-architect-grown.jsonl"
  jq -cn --arg ts "$NEW_TS" '{timestamp:$ts,type:"assistant",message:{id:"architect-grown-turn",usage:{input_tokens:5,cache_creation_input_tokens:6,cache_read_input_tokens:7,output_tokens:8},content:[{type:"tool_use"}]}}' >> "$SESSION/subagents/agent-architect-grown.jsonl"
  sleep 2
  run_accounting || exit 1
  jq -e --arg first "$FIRST_BOUND" '
    ._posthoc.run_ended_at != $first and
    ._posthoc.basis == {spawn_events:3,conductor_legs:1} and
    ([.specialist_spawns[] | select(.role.value == "architect")] | length) == 1 and
    (.specialist_spawns[] | select(.role.value == "architect")
      | .tokens.processed == {value:18,confidence:"exact"})
  ' "$RP/accounting.json" >/dev/null || exit 1
  echo "PASS"
  # Mutations: force `now` instead of reusing the prior bound and the delayed
  # second close-out differs byte-for-byte. Always reuse the old bound despite a
  # basis change and the post-bound architect usage is excluded/zero, failing 18.
expected: exit 0; stdout "PASS"; delayed no-op close-out is byte-identical with the same bound, then one appended SPAWN-EVENT changes basis 2→3, advances the bound, and accounts the post-first-bound architect at processed 18 exact
phase: 04 · execute-plan
owner: Prompt 04 / account-run.sh W4 run-ended-at read-back and growth basis
