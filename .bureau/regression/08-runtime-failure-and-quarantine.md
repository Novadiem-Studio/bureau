name: Runtime failure and setup quarantine
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  set -eu
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  C="$ROOT/docs/codebase-readiness-audit-contract.md"
  W="$ROOT/workflows/codebase-readiness-audit.md"
  strip "$C" | grep -Fq 'A failed or missing runnable environment is `unverifiable`, never a pass.'
  strip "$C" | grep -Fq '`audit/setup-quarantine.md` is always present.'
  strip "$C" | grep -Fq '`approved_client_fix: false`.'
  strip "$W" | grep -Fq 'an explicit no-change quarantine is still required.'
  printf '%s\n' 'PASS runtime failure and quarantine contract'
expected: exact stdout: PASS runtime failure and quarantine contract
phase: 05 · execute-plan
owner: plan/05-registration-and-scratch-regressions.md
