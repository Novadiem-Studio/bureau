name: Exact readiness profiles and observable depth
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  set -eu
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  C="$ROOT/docs/codebase-readiness-audit-contract.md"
  test -f "$ROOT/agents/critic/readiness-audit.md"
  strip "$ROOT/check-framework.sh" | grep -Fq 'for slice in spec-plan prompts build-diff code-review readiness-audit; do'
  strip "$ROOT/agents/critic.md" | grep -Fq 'agents/critic/readiness-audit.md'
  strip "$C" | grep -Fq -- '- Audit profile: `catalog | full | audited`.'
  strip "$C" | grep -Fq '`catalog` performs independent static deep-read coverage'
  strip "$C" | grep -Fq '`full` adds isolated local stand-up, synthetic lifecycle probes'
  strip "$C" | grep -Fq '`audited` includes all `full` obligations and adds a fresh premium Challenger cold review'
  strip "$C" | grep -Fq 'There is no default profile.'
  printf '%s\n' 'PASS readiness slice registration and exact profile depth'
expected: exact stdout: PASS readiness slice registration and exact profile depth
phase: 05 · execute-plan
owner: plan/05-registration-and-scratch-regressions.md
