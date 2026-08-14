name: aggregate-transcripts keeps incomplete nonzero usage partial across every leg class
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM

  make_run() {
    case_name="$1"
    target="$TMPF/$case_name-target"
    run_path="$target/.bureau/runs/$case_name-run"
    projects="$TMPF/$case_name-projects"
    sid="delegate-$case_name"
    munged=$(printf '%s' "$target" | sed 's#[/.]#-#g')
    session="$projects/$munged/$sid"
    pointer="$TMPF/$case_name-pointer"
    mkdir -p "$run_path" "$session/subagents"
    printf '%s\n' '{"runtime":"claude"}' > "$run_path/model-routing.json"
    jq -cn --arg target "$target" '{target_repo:$target}' > "$run_path/state.json"
    jq -cn --arg sid "$sid" --arg cond "cond-$case_name" \
      '{delegate_session_id:$sid,conductor_agent_id:$cond,conductor_agent_ids:[$cond],run_started_at:"2026-08-13T00:00:01Z"}' \
      > "$run_path/delegate-state.json"
    printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-%s","status":"started"}\n' "$case_name" > "$run_path/log.md"
    jq -cn --arg run "$run_path" --arg nonce "nonce-$case_name" \
      '{run_dir:$run,nonce:$nonce,written_at:"2026-08-13T00:00:00Z"}' > "$pointer"
  }

  # Incomplete but summable: each window has real nonzero usage and omits at
  # least one required token field. Every class must retain the usable subtotal,
  # become partial, and carry the degradation note.
  make_run partial
  PARTIAL_TARGET="$TMPF/partial-target"
  PARTIAL_RUN="$PARTIAL_TARGET/.bureau/runs/partial-run"
  PARTIAL_PROJECTS="$TMPF/partial-projects"
  PARTIAL_M=$(printf '%s' "$PARTIAL_TARGET" | sed 's#[/.]#-#g')
  PARTIAL_SESSION="$PARTIAL_PROJECTS/$PARTIAL_M/delegate-partial"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"delegate-partial-turn","usage":{"input_tokens":5,"cache_creation_input_tokens":3,"output_tokens":2},"content":[{"type":"tool_use"}]}}' > "$PARTIAL_SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"conductor-partial-turn","usage":{"input_tokens":4,"cache_read_input_tokens":6,"output_tokens":1},"content":[{"type":"tool_use"}]}}' > "$PARTIAL_SESSION/subagents/agent-cond-partial.jsonl"
  jq -cn --arg run "$PARTIAL_RUN" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-partial\nRun nonce: nonce-partial\n")}}' > "$PARTIAL_SESSION/subagents/agent-specialist-partial.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"specialist-partial-turn","usage":{"cache_creation_input_tokens":7,"cache_read_input_tokens":8,"output_tokens":3},"content":[{"type":"tool_use"}]}}' >> "$PARTIAL_SESSION/subagents/agent-specialist-partial.jsonl"
  jq -cn --arg run "$PARTIAL_RUN" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nRun nonce: nonce-partial\n")}}' > "$PARTIAL_SESSION/subagents/agent-unattributed-partial.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"unattributed-partial-turn","usage":{"input_tokens":2,"output_tokens":5},"content":[]}}' >> "$PARTIAL_SESSION/subagents/agent-unattributed-partial.jsonl"

  partial_out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PARTIAL_PROJECTS" BUREAU_POINTER_FILE="$TMPF/partial-pointer" \
    "$ROOT/scripts/aggregate-transcripts.sh" "$PARTIAL_RUN" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$partial_out" | jq -e '
    .delegate.tokens == {input:5,cache_creation:3,cache_read:0,processed:8,output:2}
    and .delegate.turns == 1 and .delegate.confidence == "partial"
    and (.delegate._note | contains("incomplete message usage token fields"))
    and .conductor.tokens == {input:4,cache_creation:0,cache_read:6,processed:10,output:1}
    and .conductor.turns == 1 and .conductor.legs == 1 and .conductor.confidence == "partial"
    and (.conductor._note | contains("incomplete message usage token fields"))
    and ([.specialists[] | select(.attempt_id == "analyst-partial")][0]
      | .tokens == {input:0,cache_creation:7,cache_read:8,processed:15,output:3}
        and .turns == 1 and .confidence == "partial"
        and (._note | contains("incomplete message usage token fields")))
    and ([.specialists[] | select(.attempt_id == null)][0]
      | .role == null and .agent_id == "unattributed-partial"
        and .tokens == {input:2,cache_creation:0,cache_read:0,processed:2,output:5}
        and .turns == 0 and .confidence == "partial"
        and (._note | contains("counted as unattributed"))
        and (._note | contains("incomplete message usage token fields")))
  ' >/dev/null || exit 1

  # Complete nonzero control: the same four classes retain their established
  # exact/inferred dispositions and never acquire the incomplete-fields note.
  make_run complete
  COMPLETE_TARGET="$TMPF/complete-target"
  COMPLETE_RUN="$COMPLETE_TARGET/.bureau/runs/complete-run"
  COMPLETE_PROJECTS="$TMPF/complete-projects"
  COMPLETE_M=$(printf '%s' "$COMPLETE_TARGET" | sed 's#[/.]#-#g')
  COMPLETE_SESSION="$COMPLETE_PROJECTS/$COMPLETE_M/delegate-complete"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"delegate-complete-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4},"content":[{"type":"tool_use"}]}}' > "$COMPLETE_SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"conductor-complete-turn","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4,"output_tokens":5},"content":[{"type":"tool_use"}]}}' > "$COMPLETE_SESSION/subagents/agent-cond-complete.jsonl"
  jq -cn --arg run "$COMPLETE_RUN" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-complete\nRun nonce: nonce-complete\n")}}' > "$COMPLETE_SESSION/subagents/agent-specialist-complete.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"specialist-complete-turn","usage":{"input_tokens":3,"cache_creation_input_tokens":4,"cache_read_input_tokens":5,"output_tokens":6},"content":[{"type":"tool_use"}]}}' >> "$COMPLETE_SESSION/subagents/agent-specialist-complete.jsonl"
  jq -cn --arg run "$COMPLETE_RUN" '{type:"user",message:{content:("RUN_DIR: "+$run+"\nRun nonce: nonce-complete\n")}}' > "$COMPLETE_SESSION/subagents/agent-unattributed-complete.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"unattributed-complete-turn","usage":{"input_tokens":4,"cache_creation_input_tokens":5,"cache_read_input_tokens":6,"output_tokens":7},"content":[{"type":"tool_use"}]}}' >> "$COMPLETE_SESSION/subagents/agent-unattributed-complete.jsonl"

  complete_out=$(BUREAU_CLAUDE_PROJECTS_DIR="$COMPLETE_PROJECTS" BUREAU_POINTER_FILE="$TMPF/complete-pointer" \
    "$ROOT/scripts/aggregate-transcripts.sh" "$COMPLETE_RUN" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$complete_out" | jq -e '
    .delegate.tokens.processed == 6 and .delegate.confidence == "exact" and (.delegate | has("_note") | not)
    and .conductor.tokens.processed == 9 and .conductor.confidence == "exact" and (.conductor | has("_note") | not)
    and ([.specialists[] | select(.attempt_id == "analyst-complete")][0]
      | .tokens.processed == 12 and .confidence == "exact" and (has("_note") | not))
    and ([.specialists[] | select(.attempt_id == null)][0]
      | .tokens.processed == 15 and .confidence == "inferred"
        and (._note | contains("counted as unattributed"))
        and (._note | contains("incomplete message usage token fields") | not))
  ' >/dev/null || exit 1

  # Discovered-Conductor branch: no recorded id, but a run-scoped transcript whose
  # BUREAU_ROLE marker precedes any Attempt ID. Incomplete nonzero usage must add its
  # own note independently of the separate discovery-based partial disposition.
  make_run discovered-partial
  DISC_PARTIAL_TARGET="$TMPF/discovered-partial-target"
  DISC_PARTIAL_RUN="$DISC_PARTIAL_TARGET/.bureau/runs/discovered-partial-run"
  DISC_PARTIAL_PROJECTS="$TMPF/discovered-partial-projects"
  DISC_PARTIAL_M=$(printf '%s' "$DISC_PARTIAL_TARGET" | sed 's#[/.]#-#g')
  DISC_PARTIAL_SESSION="$DISC_PARTIAL_PROJECTS/$DISC_PARTIAL_M/delegate-discovered-partial"
  jq -cn --arg sid "delegate-discovered-partial" \
    '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' \
    > "$DISC_PARTIAL_RUN/delegate-state.json"
  jq -cn --arg run "$DISC_PARTIAL_RUN" \
    '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$run+"\n")}}' \
    > "$DISC_PARTIAL_SESSION/subagents/agent-discovered-partial.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"discovered-partial-turn","usage":{"input_tokens":4,"output_tokens":1},"content":[{"type":"tool_use"}]}}' \
    >> "$DISC_PARTIAL_SESSION/subagents/agent-discovered-partial.jsonl"
  discovered_partial_out=$(BUREAU_CLAUDE_PROJECTS_DIR="$DISC_PARTIAL_PROJECTS" \
    BUREAU_POINTER_FILE="$TMPF/discovered-partial-pointer" \
    "$ROOT/scripts/aggregate-transcripts.sh" "$DISC_PARTIAL_RUN" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$discovered_partial_out" | jq -e '
    .conductor.tokens == {input:4,cache_creation:0,cache_read:0,processed:4,output:1}
    and .conductor.turns == 1 and .conductor.legs == 1
    and .conductor.confidence == "partial"
    and (.conductor._note | contains("incomplete message usage token fields"))
    and (.conductor._note | contains("unrecorded conductor-marked leg"))
  ' >/dev/null || exit 1

  # Complete discovered control remains partial solely because discovery is not a
  # recorded identity, and must not acquire the incomplete-usage note.
  make_run discovered-complete
  DISC_COMPLETE_TARGET="$TMPF/discovered-complete-target"
  DISC_COMPLETE_RUN="$DISC_COMPLETE_TARGET/.bureau/runs/discovered-complete-run"
  DISC_COMPLETE_PROJECTS="$TMPF/discovered-complete-projects"
  DISC_COMPLETE_M=$(printf '%s' "$DISC_COMPLETE_TARGET" | sed 's#[/.]#-#g')
  DISC_COMPLETE_SESSION="$DISC_COMPLETE_PROJECTS/$DISC_COMPLETE_M/delegate-discovered-complete"
  jq -cn --arg sid "delegate-discovered-complete" \
    '{delegate_session_id:$sid,run_started_at:"2026-08-13T00:00:01Z"}' \
    > "$DISC_COMPLETE_RUN/delegate-state.json"
  jq -cn --arg run "$DISC_COMPLETE_RUN" \
    '{type:"user",message:{content:("BUREAU_ROLE: conductor\nRUN_DIR: "+$run+"\n")}}' \
    > "$DISC_COMPLETE_SESSION/subagents/agent-discovered-complete.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"discovered-complete-turn","usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4,"output_tokens":5},"content":[{"type":"tool_use"}]}}' \
    >> "$DISC_COMPLETE_SESSION/subagents/agent-discovered-complete.jsonl"
  discovered_complete_out=$(BUREAU_CLAUDE_PROJECTS_DIR="$DISC_COMPLETE_PROJECTS" \
    BUREAU_POINTER_FILE="$TMPF/discovered-complete-pointer" \
    "$ROOT/scripts/aggregate-transcripts.sh" "$DISC_COMPLETE_RUN" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$discovered_complete_out" | jq -e '
    .conductor.tokens.processed == 9 and .conductor.legs == 1
    and .conductor.confidence == "partial"
    and (.conductor._note | contains("unrecorded conductor-marked leg"))
    and (.conductor._note | contains("incomplete message usage token fields") | not)
  ' >/dev/null || exit 1

  # Legacy key=value SPAWN-EVENT membership is parsed identically by the producer
  # and both consumers, so it cannot disappear into an exact empty-specialist result.
  make_run keyvalue
  KEY_TARGET="$TMPF/keyvalue-target"
  KEY_RUN="$KEY_TARGET/.bureau/runs/keyvalue-run"
  KEY_PROJECTS="$TMPF/keyvalue-projects"
  KEY_M=$(printf '%s' "$KEY_TARGET" | sed 's#[/.]#-#g')
  KEY_SESSION="$KEY_PROJECTS/$KEY_M/delegate-keyvalue"
  printf '%s\n' \
    'SPAWN-EVENT: role=analyst agent=analyst configured_model=sonnet actual_model=sonnet attempt=1 attempt_id=analyst-keyvalue status=started at=2026-08-13T00:00:00Z' \
    > "$KEY_RUN/log.md"
  jq -cn --arg run "$KEY_RUN" \
    '{type:"user",message:{content:("RUN_DIR: "+$run+"\nAttempt ID: analyst-keyvalue\nRun nonce: nonce-keyvalue\n")}}' \
    > "$KEY_SESSION/subagents/agent-keyvalue.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"keyvalue-turn","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4},"content":[]}}' \
    >> "$KEY_SESSION/subagents/agent-keyvalue.jsonl"
  keyvalue_out=$(BUREAU_CLAUDE_PROJECTS_DIR="$KEY_PROJECTS" BUREAU_POINTER_FILE="$TMPF/keyvalue-pointer" \
    "$ROOT/scripts/aggregate-transcripts.sh" "$KEY_RUN" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$keyvalue_out" | jq -e '
    ([.specialists[] | select(.attempt_id == "analyst-keyvalue")][0]
      | .role == "analyst" and .agent_id == "keyvalue"
        and .tokens.processed == 6 and .confidence == "exact")
  ' >/dev/null || exit 1
  printf '%s\n' "$keyvalue_out" > "$TMPF/keyvalue-fragment.json"
  keyvalue_metrics=$(bash "$ROOT/scripts/account-tokens.sh" "$KEY_RUN" "$TMPF/keyvalue-fragment.json") || exit 1
  printf '%s' "$keyvalue_metrics" | jq -e '
    .tokens.processed_total.value == 6
    and .tokens.processed_total.confidence == "partial"
  ' >/dev/null || exit 1

  echo PASS
  # Mutations: restore the nonzero shortcut and incomplete rows become exact/inferred;
  # delete either recorded or discovered partial propagation and its branch-specific
  # note assertion fails; drop key=value membership parsing and the final case fails.
expected: exit 0; stdout "PASS"; incomplete nonzero Delegate, recorded/discovered Conductor, specialist, and unattributed windows retain usable subtotals as noted partial legs, complete controls retain their identity-appropriate disposition, and legacy key=value membership remains visible
phase: integration hardening
owner: aggregate-transcripts incomplete-usage confidence seam
