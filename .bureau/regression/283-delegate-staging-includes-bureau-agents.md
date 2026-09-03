name: delegate-staging-includes-bureau-agents (D5 — delegate.md staging manifest includes bureau-agents.md step)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: agents/delegate.md — staging manifest includes bureau-agents.md (D5 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  # delegate.md must mention bureau-agents.md in the staging context
  strip "$ROOT/agents/delegate.md" | grep -qF 'bureau-agents.md' \
    || { echo 'FAIL: agents/delegate.md does not mention bureau-agents.md in staging'; exit 1; }
  # Must also document the cp AGENTS.md step
  strip "$ROOT/agents/delegate.md" | grep -qF 'AGENTS.md' \
    || { echo 'FAIL: agents/delegate.md does not reference AGENTS.md in staging'; exit 1; }
  echo "PASS"
  # Mutation note: delete the bureau-agents.md bullet (including the cp line) from
  # agents/delegate.md step-3 staging manifest. The grep-qF 'bureau-agents.md'
  # check fails and the fixture exits 1.
expected: PASS
