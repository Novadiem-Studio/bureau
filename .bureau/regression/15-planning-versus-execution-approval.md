name: Planning eligibility versus execution approval
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  set -eu
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  C="$ROOT/docs/codebase-readiness-audit-contract.md"
  W="$ROOT/workflows/codebase-readiness-audit.md"
  strip "$C" | grep -Fq 'Remediation planning needs no client-fix approval, creates no approval'
  strip "$C" | grep -Fq 'That handoff may authorize the Conductor to start a separate execute-plan run.'
  strip "$C" | grep -Fq 'requested_next_workflow: execute-plan'
  strip "$C" | grep -Fq '`seal_sha256` | `sha256` | Hash of that exact seal.'
  strip "$C" | grep -Fq '`remediation_plan_sha256` | `sha256` | Hash of that exact completed `plan.md`.'
  strip "$W" | grep -Fq 'This is a separately invoked Conductor re-entry after remediation planning is complete.'
  strip "$W" | grep -Fq 'This workflow does not invoke it'
  strip "$W" | grep -Fq 'Retain an incomplete archival seal only as non-selectable evidence.'
  printf '%s\n' 'PASS planning versus execution approval re-entry'
expected: exact stdout: PASS planning versus execution approval re-entry
phase: 05 · execute-plan
owner: plan/05-registration-and-scratch-regressions.md
