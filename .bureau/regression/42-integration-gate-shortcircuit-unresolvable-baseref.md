name: F03 · integration-gate.sh short-circuit escalate-marker — unresolvable base-ref
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo x > "$W/a.txt"; git -C "$W" add -A; git -C "$W" commit -qm base
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref no-such-ref-xyz \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  jq -e '.escalate_marker!="" and (has("verdict")|not)' "$TMP/ctx/integration-results.json"
expected: exit 0 — a base-ref that does not resolve in the worktree makes the short-circuit guard set escalate_marker non-empty, and there is NO "verdict" key. Nonzero if the unresolvable-base-ref short-circuit guard is removed (the full gate path then leaves escalate_marker=="").
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
