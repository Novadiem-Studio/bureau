name: F04 · integration-gate.sh under-declaration — claimed-gates declares fewer than the canonical runner
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W/.bureau/regression" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  jq -e '(.under_declaration|length>0) and (has("verdict")|not)' "$TMP/ctx/integration-results.json"
expected: exit 0 — the canonical regression runner is resolved from the project but claimed-gates is empty, so under_declaration records the un-declared canonical gate(s) (non-empty); NO "verdict" key. Nonzero if the under-declaration cross-check is neutralized (under_declaration stays []).
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
