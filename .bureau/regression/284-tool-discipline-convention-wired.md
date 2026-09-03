name: tool-discipline-convention-wired (CONV — tool-discipline module exists and is referenced from conventions router + all specialist agents)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: docs/conventions/tool-discipline.md + docs/conventions.md + agents/* (CONV 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  # 1. Module file exists
  [ -f "$ROOT/docs/conventions/tool-discipline.md" ] \
    || { echo 'FAIL: docs/conventions/tool-discipline.md does not exist'; exit 1; }
  # 2. Router entry exists in docs/conventions.md
  strip "$ROOT/docs/conventions.md" | grep -qF 'tool-discipline.md' \
    || { echo 'FAIL: docs/conventions.md has no tool-discipline.md entry'; exit 1; }
  # 3. All specialist agent files carry the pointer
  fail=0
  for agent in analyst architect critic designer prompt-engineer voice frontend backend sysadmin; do
    strip "$ROOT/agents/$agent.md" | grep -qF 'tool-discipline.md' \
      || { echo "FAIL: agents/$agent.md missing tool-discipline.md pointer"; fail=1; }
  done
  # 4. orchestrator.md carries the pointer
  strip "$ROOT/agents/orchestrator.md" | grep -qF 'tool-discipline.md' \
    || { echo 'FAIL: agents/orchestrator.md missing tool-discipline.md pointer'; fail=1; }
  [ "$fail" -eq 0 ] || exit 1
  echo "PASS"
  # Mutation note: delete the tool-discipline.md entry from docs/conventions.md.
  # The grep-qF check in step 2 fails and the fixture exits 1.
expected: PASS
