name: Audited packet and adapter rejection surface
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  set -eu
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  S="$ROOT/scripts/run-cold-reviewer.sh"
  strip "$S" | grep -Fq 'regular-file set does not exactly match packet.json plus allowlist'
  strip "$S" | grep -Fq 'contains a symlink:'
  strip "$S" | grep -Fq 'path escapes packet root:'
  strip "$S" | grep -Fq 'allowlist contains forbidden run-history basename:'
  strip "$S" | grep -Fq 'sha256 is missing, uppercase, or malformed'
  strip "$S" | grep -Fq 'staged payload hash mismatch:'
  strip "$S" | grep -Fq 'no-clobber publication collision:'
  strip "$S" | grep -Fq 'reviewed_artifacts does not exactly match ordered packet allowlist'
  printf '%s\n' 'PASS audited packet and adapter reject malformed collision cases'
expected: exact stdout: PASS audited packet and adapter reject malformed collision cases
phase: 05 · execute-plan
owner: plan/05-registration-and-scratch-regressions.md
