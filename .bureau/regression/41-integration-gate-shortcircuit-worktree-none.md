name: F02 · integration-gate.sh short-circuit escalate-marker — worktree=(none)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/ctx"
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "(none)" --base-ref devel \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  jq -e '.escalate_marker!="" and .fast_forward_ok==false and .conflicts_clean==false and (has("verdict")|not)' "$TMP/ctx/integration-results.json"
expected: exit 0 — with --worktree-path "(none)" the short-circuit guard sets escalate_marker non-empty, fast_forward_ok==false, conflicts_clean==false, and NO "verdict" key. Nonzero if the (none)-worktree short-circuit guard is removed (the full gate path then leaves escalate_marker=="").
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
