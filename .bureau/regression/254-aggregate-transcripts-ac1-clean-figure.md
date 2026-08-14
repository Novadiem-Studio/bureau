name: aggregate-transcripts AC1 clean figure stays exact on a hermetic single-run session
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT
  TARGET="$TMPF/target"
  RUN_PATH="$TARGET/.bureau/runs/single-run"
  PROJECTS="$TMPF/projects"
  SID="delegate-single-run"
  M=$(printf '%s' "$TARGET" | sed 's#[/.]#-#g')
  TRANSCRIPT="$PROJECTS/$M/$SID.jsonl"
  mkdir -p "$RUN_PATH" "$(dirname "$TRANSCRIPT")"
  printf '{"runtime":"claude"}\n' > "$RUN_PATH/model-routing.json"
  jq -cn --arg target "$TARGET" '{target_repo:$target}' > "$RUN_PATH/state.json"
  printf '{}\n' > "$RUN_PATH/delegate-state.json"
  printf 'DELEGATE-TOKEN-EVENT: {"session_id":"%s","final":true}\n' "$SID" > "$RUN_PATH/log.md"
  jq -cn --arg own "$RUN_PATH" --arg foreign "$TARGET/.bureau/runs/foreign-run" \
    '{type:"user",message:{content:("RUN_DIR: "+$own+"\nTool output mentions "+$foreign+" without a RUN_DIR header\n")}}' \
    > "$TRANSCRIPT"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"single-turn","usage":{"input_tokens":7,"cache_creation_input_tokens":11,"cache_read_input_tokens":13,"output_tokens":17},"content":[{"type":"tool_use"}]}}' \
    >> "$TRANSCRIPT"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" BUREAU_POINTER_FILE="$TMPF/no-pointer" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>/dev/null) || exit 1
  printf '%s' "$out" | jq -e '
    .delegate.tokens == {input:7,cache_creation:11,cache_read:13,processed:31,output:17} and
    .delegate.turns == 1 and
    .delegate.confidence == "exact" and
    (.delegate | has("_note") | not)
  ' >/dev/null || exit 1
  echo "PASS"
  # Mutation: count bare run-path mentions as RUN_DIR headers or remove the
  # own-only header test; the synthetic single-run leg becomes partial.
expected: exit 0; stdout "PASS"; synthetic single-run Delegate usage is processed=31, turns=1, confidence exact
phase: 03 · execute-plan
owner: Prompt 03 / AC1 hermetic clean-figure proof
