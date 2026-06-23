name: Bundle 14 P4 — Delegate persona has Verifying mode section, staged-file trigger (not checkpoint-type), enumerated severity markers, integration-results.json whitelisted
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  D="$ROOT/agents/delegate.md"
  grep -q '## Verifying mode (integration checkpoints)' "$D" || { echo "verifying-mode section missing"; exit 1; }
  # trigger keys on staged-file presence, NOT checkpoint-type
  grep -q 'integration-results.json' "$D" || { echo "integration-results.json not referenced"; exit 1; }
  grep -Eiq 'do NOT check.*checkpoint-type' "$D" || { echo "missing explicit do-not-check-checkpoint-type guard"; exit 1; }
  # enumerated severity markers (FR-44 boundary) — sample a few keywords
  grep -q 'data-loss' "$D" && grep -q 'credential' "$D" || { echo "enumerated severity marker list missing"; exit 1; }
  # existing critic checklist still present (additive guarantee)
  grep -q '## Critic checklist' "$D" || { echo "existing critic checklist clobbered"; exit 1; }
  echo PASS
expected: exit 0 — prints PASS; nonzero if the verifying-mode section, the staged-file trigger guard, the enumerated severity list, or the existing critic checklist are missing
phase: 04 · execute-plan (Bundle 14)
owner: prompts.md Prompt 4 (agents/delegate.md)
