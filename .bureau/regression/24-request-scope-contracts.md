name: Bundle 14 P1 — request schema + state.json scope block + orchestrator classifier present
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  python3 -c "import json,sys; d=json.load(open('$ROOT/templates/state.json')); s=d.get('scope'); assert isinstance(s,dict) and set(s)>={'allowed_paths','cut_symbols','declared_at','declared_by'}, 'scope block missing/incomplete'; print('state.json scope OK')" || exit 1
  grep -q 'checkpoint-type:' "$ROOT/docs/delegate-bridge.md" || { echo 'checkpoint-type field missing from delegate-bridge.md'; exit 1; }
  grep -q 'claimed-gates:' "$ROOT/docs/delegate-bridge.md" || { echo 'claimed-gates field missing'; exit 1; }
  grep -q 'Step 0 — Classify the checkpoint' "$ROOT/agents/orchestrator.md" || { echo 'classifier Step 0 missing from orchestrator.md'; exit 1; }
  echo PASS
expected: exit 0 — prints "state.json scope OK" then "PASS"; nonzero if the scope block, the new request fields, or the orchestrator classifier step are missing
phase: 01 · execute-plan (Bundle 14)
owner: prompts.md Prompt 1 (docs/delegate-bridge.md §2, templates/state.json, agents/orchestrator.md)
