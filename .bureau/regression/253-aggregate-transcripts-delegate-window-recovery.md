name: aggregate-transcripts windows every leg and labels resolved, shared, single-run, legacy-record, and unavailable Delegate recovery honestly
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  TARGET="$TMPF/target"
  PROJECTS="$TMPF/projects"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g')
  UNTIL="2026-08-13T00:00:03Z"

  make_run() {
    slug="$1"; sid="$2"
    CASE_RUN="$TMPF/.bureau/runs/$slug"
    CASE_SESSION="$PROJECTS/$M/$sid"
    mkdir -p "$CASE_RUN" "$CASE_SESSION/subagents"
    printf '{"runtime":"claude"}\n' > "$CASE_RUN/model-routing.json"
    jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$CASE_RUN/state.json"
    : > "$CASE_RUN/log.md"
  }

  # Resolved Delegate window. The same upper bound applies to Conductor and
  # specialist legs, but only Delegate receives the lower bound.
  make_run resolved delegate-resolved
  jq -cn --arg sid "delegate-resolved" '{delegate_session_id:$sid,conductor_agent_id:"cond",conductor_agent_ids:["cond"],run_started_at:"2026-08-13T00:00:01Z"}' > "$CASE_RUN/delegate-state.json"
  printf 'SPAWN-EVENT: {"role":"analyst","attempt_id":"analyst-1","status":"started"}\n' > "$CASE_RUN/log.md"
  printf '%s\n' \
    '{"timestamp":"2026-08-13T00:00:00Z","type":"assistant","message":{"id":"d-before","usage":{"input_tokens":90,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"d-in","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[{"type":"tool_use"}]}}' \
    '{"timestamp":"2026-08-13T00:00:03Z","type":"assistant","message":{"id":"d-upper","usage":{"input_tokens":80,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    > "$CASE_SESSION.jsonl"
  jq -cn --arg run "$CASE_RUN" '{type:"user",message:{content:("BUREAU_ROLE: conductor\\nRUN_DIR: "+$run+"\\n")}}' > "$CASE_SESSION/subagents/agent-cond.jsonl"
  printf '%s\n' \
    '{"timestamp":"2026-08-12T23:59:59Z","type":"assistant","message":{"id":"c-early","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    '{"timestamp":"2026-08-13T00:00:03Z","type":"assistant","message":{"id":"c-upper","usage":{"input_tokens":70,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    >> "$CASE_SESSION/subagents/agent-cond.jsonl"
  jq -cn --arg run "$CASE_RUN" '{type:"user",message:{content:("RUN_DIR: "+$run+"\\nAttempt ID: analyst-1\\n")}}' > "$CASE_SESSION/subagents/agent-analyst.jsonl"
  printf '%s\n' \
    '{"timestamp":"2026-08-12T23:59:58Z","type":"assistant","message":{"id":"s-early","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    '{"timestamp":"2026-08-13T00:00:03Z","type":"assistant","message":{"id":"s-upper","usage":{"input_tokens":60,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' \
    >> "$CASE_SESSION/subagents/agent-analyst.jsonl"
  resolved=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/no-pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$CASE_RUN" --until "$UNTIL") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$resolved" | jq -e '
    .delegate.tokens.processed == 2 and .delegate.turns == 1 and .delegate.confidence == "exact" and
    .conductor.tokens.processed == 3 and .conductor.confidence == "exact" and
    .specialists[0].tokens.processed == 4 and .specialists[0].confidence == "exact"
  ' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  # Unresolvable shared session: two concrete framework headers force partial.
  make_run shared delegate-shared
  jq -cn --arg sid "delegate-shared" '{delegate_session_id:$sid}' > "$CASE_RUN/delegate-state.json"
  SIBLING="$TMPF/.bureau/runs/sibling"
  jq -cn --arg own "$CASE_RUN" --arg sibling "$SIBLING" '{type:"user",message:{content:("RUN_DIR: "+$own+"\\nRUN_DIR: "+$sibling+"\\n")}}' > "$CASE_SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"shared","usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$CASE_SESSION.jsonl"
  shared=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$CASE_RUN" --until "$UNTIL") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$shared" | jq -e '.delegate.tokens.processed==5 and .delegate.confidence=="partial" and (.delegate._note|contains("may over-attribute sibling-run turns"))' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  # Own concrete header plus foreign bare mentions remains single-run exact.
  make_run single delegate-single
  jq -cn --arg sid "delegate-single" '{delegate_session_id:$sid}' > "$CASE_RUN/delegate-state.json"
  FOREIGN1="$TMPF/.bureau/runs/foreign-one"; FOREIGN2="$TMPF/output/runs/foreign-two"
  jq -cn --arg own "$CASE_RUN" --arg f1 "$FOREIGN1" --arg f2 "$FOREIGN2" '{type:"user",message:{content:("RUN_DIR: "+$own+"\\nTool result mentions "+$f1+" and "+$f2+" without headers\\n")}}' > "$CASE_SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"single","usage":{"input_tokens":6,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$CASE_SESSION.jsonl"
  single=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$CASE_RUN" --until "$UNTIL") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$single" | jq -e '.delegate.tokens.processed==6 and .delegate.confidence=="exact" and (.delegate|has("_note")|not)' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  # A legacy record supplies the key when delegate-state lacks it.
  make_run legacy delegate-legacy
  printf '{}\n' > "$CASE_RUN/delegate-state.json"
  printf 'DELEGATE-TOKEN-EVENT: {"session_id":"delegate-legacy","final":true}\n' > "$CASE_RUN/log.md"
  jq -cn --arg own "$CASE_RUN" '{type:"user",message:{content:("RUN_DIR: "+$own+"\\n")}}' > "$CASE_SESSION.jsonl"
  printf '%s\n' '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"legacy","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[]}}' >> "$CASE_SESSION.jsonl"
  legacy=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$CASE_RUN" --until "$UNTIL") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$legacy" | jq -e '.delegate.tokens.processed==7 and .delegate.confidence=="exact"' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  # Neither live nor legacy key produces an honest unavailable record.
  make_run unavailable delegate-unused
  printf '{}\n' > "$CASE_RUN/delegate-state.json"
  unavailable=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$CASE_RUN" --until "$UNTIL") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$unavailable" | jq -e '.delegate.tokens.processed==0 and .delegate.confidence=="unavailable" and (.delegate._note|contains("session id not recorded"))' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutations: dropping timestamp bounds admits the 60/70/80-token upper lines;
  # deleting the single-run test makes single partial; counting bare paths also
  # makes single partial; deleting legacy precedence makes legacy unavailable.
expected: exit 0; stdout "PASS"; Delegate is [since,until), every other leg is until-bounded without since, and all key/confidence recovery states are pinned
phase: 02 · execute-plan
owner: Prompt 02 / aggregate-transcripts.sh Delegate recovery and confidence seam
