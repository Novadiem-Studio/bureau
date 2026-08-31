name: Audited exact-hash blocker gate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  set -eu
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  C="$ROOT/docs/codebase-readiness-audit-contract.md"
  W="$ROOT/workflows/codebase-readiness-audit.md"
  strip "$C" | grep -Fq 'non-`BLOCKED` verdict bound to the exact corrected-audit version, path, and hash being sealed.'
  strip "$C" | grep -Fq '`BLOCKED`, malformed, stale, or differently bound verdicts prevent sealing.'
  strip "$C" | grep -Fq '`corrected_audit_sha256` | `sha256` | Equals the corrected event hash and exact file bytes.'
  strip "$W" | grep -Fq 'A canonical `BLOCKED` verdict requires correction in a newly allocated audit version'
  printf '%s\n' 'PASS audited exact-hash blocker gate'
expected: exact stdout: PASS audited exact-hash blocker gate
phase: 05 · execute-plan
owner: plan/05-registration-and-scratch-regressions.md
