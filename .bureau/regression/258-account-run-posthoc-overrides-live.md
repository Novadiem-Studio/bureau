name: account-run post-hoc-overrides-live — aggregator legs and derived metrics are one authoritative source while hook figures remain inert
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT
  TARGET="$TMPF/target"
  RP="$TARGET/.bureau/runs/20260813-authoritative"
  PROJECTS="$TMPF/projects"
  SID="delegate-authoritative"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g')
  SESSION="$PROJECTS/$M/$SID"
  mkdir -p "$RP" "$SESSION/subagents"

  printf '{"runtime":"claude"}\n' > "$RP/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target,workflow:"feature",phase_status:"complete",phases_complete:["analyst"],critic_loops:{analyst:2}}' > "$RP/state.json"
  jq -cn --arg sid "$SID" '{delegate_session_id:$sid,conductor_agent_id:"cond-real",conductor_agent_ids:["cond-real"],run_started_at:"2026-08-13T00:00:00Z"}' > "$RP/delegate-state.json"
  jq -cn --arg run "$RP" '{run_dir:$run,nonce:"nonce-authoritative",written_at:"2026-08-12T23:59:59Z"}' > "$TMPF/pointer"

  # Live hooks deliberately report different figures. They must remain present
  # but become inert whenever the post-hoc contract is usable.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:01Z","rework":true}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-08-13T00:00:02Z","started_at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"specialist-real","at":"2026-08-13T00:00:02Z","turns":9,"tokens":{"input":700,"cache_creation":0,"cache_read":0,"processed":700,"output":70}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"live-c","at":"2026-08-13T00:00:02Z","turns":9,"tokens":{"input":900,"cache_creation":0,"cache_read":0,"processed":900,"output":90},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"live-d","at":"2026-08-13T00:00:02Z","turns":9,"tokens":{"input":800,"cache_creation":0,"cache_read":0,"processed":800,"output":80},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"spawn_id":"review-1","turns":1,"tokens":{"input":13,"cache_creation":0,"cache_read":0,"processed":13,"output":13}}' \
    'CHECKPOINT-EVENT: {"id":"05","status":"raised","at":"2026-08-13T00:00:01Z"}' \
    'CHECKPOINT-EVENT: {"id":"05","status":"resolved","at":"2026-08-13T00:00:03Z","decision":"continue"}' \
    > "$RP/log.md"

  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"delegate-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4},"content":[{"type":"tool_use"}]}}' > "$SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"cond-turn","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40},"content":[{"type":"tool_use"}]}}' > "$SESSION/subagents/agent-cond-real.jsonl"
  jq -cn --arg run "$RP" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-1\nRun nonce: nonce-authoritative\n")}}' > "$SESSION/subagents/agent-specialist-real.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"spec-turn","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":400},"content":[{"type":"tool_use"}]}}' >> "$SESSION/subagents/agent-specialist-real.jsonl"

  BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/pointer" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
    bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || exit 1

  # Aggregator values: delegate=6, conductor=60, specialist=600. The derived
  # build-only denominator is therefore 660, not live-hook 1600 and not zero.
  jq -e '
    .schema_version == 2 and
    .conductor_tokens.tokens.processed == 60 and .conductor_tokens.confidence == "exact" and
    .delegate_tokens.tokens.processed == 6 and .delegate_tokens.confidence == "exact" and
    .specialist_spawns[0].tokens.processed == {value:600,confidence:"exact"} and
    .specialist_spawns[0].turns == {value:1,confidence:"exact"} and
    .tokens.processed_total.value == 660 and
    .tokens.processed_total.confidence == "exact" and
    ((.tokens.rework_ratio.value - (600/660)) | fabs) < 0.000000001 and
    .tokens.tokens_per_loop.value == 330 and
    .tokens.output_total == {value:457,confidence:"estimated"} and
    .reviewer_tokens.tokens.processed == 13 and
    (.wall_clock.active_spawn_time_s | has("value")) and
    (.checkpoints.entries | length) == 1 and
    .tokens.processed_total._semantics == "processed sums per-turn cumulative usage (input + cache_creation + cache_read) across deduped messages — a billing-shaped figure that scales with turn count, not a unique-token count; use for before/after comparisons only" and
    (._posthoc.run_ended_at | type) == "string" and
    ._posthoc.basis == {spawn_events:2,conductor_legs:1}
  ' "$RP/accounting.json" >/dev/null || exit 1
  [ "$(grep -c '^SPAWN-TOKEN-EVENT: ' "$RP/log.md")" -eq 1 ] || exit 1
  [ "$(grep -c '^CONDUCTOR-TOKEN-EVENT: ' "$RP/log.md")" -eq 1 ] || exit 1
  echo "PASS"
  # Mutations: disable account-run.sh's post-hoc replacement and the 60/6/600
  # assertions read 900/800/700. Drop its fragment arg to account-tokens.sh and
  # processed_total/rework/tokens_per_loop/output_total revert to live figures.
expected: exit 0; stdout "PASS"; hook records remain present, but accounting.json uses post-hoc Delegate=6, Conductor=60, specialist=600, processed_total=660, rework_ratio=600/660, tokens_per_loop=330, output_total=457, while schema-2 reviewer/wall/checkpoint shapes and semantics remain intact
phase: 04 · execute-plan
owner: Prompt 04 / account-run.sh authoritative post-hoc merge + account-tokens.sh fragment-derived metrics
