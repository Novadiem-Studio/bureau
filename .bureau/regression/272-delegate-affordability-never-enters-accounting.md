name: Delegate affordability is structurally isolated from every accounting field
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  helper="$(strip "$ROOT/scripts/resolve-delegate-affordability.sh")"
  if printf '%s\n' "$helper" | grep -Eq 'conductor_tokens|delegate_tokens|reviewer_tokens|processed_total|accounting\.json|account-run|account-tokens'; then exit 1; fi
  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md" | grep -v '^[[:space:]]*#')"
  printf '%s\n' "$bootstrap" | grep -Fq 'this signal feeds ONLY model choice. It is NEVER written to' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq '`conductor_tokens`, `delegate_tokens`, `reviewer_tokens`, `processed_total`, or any accounting' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq 'The helper exposes no per-leg counts and neither imports nor writes accounting data.' || exit 1
  budget="$(grep -v '^[[:space:]]*#' "$ROOT/agents/orchestrator.md")"
  printf '%s\n' "$budget" | grep -Fq 'The live ClaudeUsage check belongs to the Delegate (the top session picks models); direct-Conductor fallback keeps this snapshot read.' || exit 1
  actual="$("$ROOT/scripts/resolve-delegate-affordability.sh" openai /does/not/exist)" || exit 1
  if printf '%s\n' "$actual" | grep -Eq 'conductor_tokens|delegate_tokens|reviewer_tokens|processed_total'; then exit 1; fi
expected: exits 0 only when executable helper code and output carry no accounting seam and Bootstrap states the exact hard boundary
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
