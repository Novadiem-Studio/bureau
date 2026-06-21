name: Bundle 09 — delegate verdict schema contract (7 required fields, closed, Decision enum)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '(.required|length==7) and (.additionalProperties==false) and (.properties.Decision.enum==["proceed","revise","escalate"])' $ROOT/config/delegate-verdict.schema.json
expected: exit 0 — jq prints true; nonzero/false if the verdict contract drifts (field count, openness, or Decision enum)
phase: 02 · execute-plan
owner: prompts.md Prompt 2 (config/delegate-verdict.schema.json)
