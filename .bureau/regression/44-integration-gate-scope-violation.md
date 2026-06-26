name: F05 · integration-gate.sh scope-violation — a diff file outside the declared scope
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W/.bureau/regression" "$W/src" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  echo base > "$W/src/a.txt"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  mkdir -p "$W/config"; echo secret > "$W/config/secret.txt"
  git -C "$W" add -A; git -C "$W" commit -qm violate
  printf '{"scope":{"allowed_paths":["src/*"],"cut_symbols":[]}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  jq -e '(.scope.violations|length>0) and .scope.scope_diff_clean==false and (has("verdict")|not)' "$TMP/ctx/integration-results.json"
expected: exit 0 — base...HEAD touches config/secret.txt which matches no allowed_paths glob, so scope.violations is non-empty and scope.scope_diff_clean==false; NO "verdict" key. Nonzero if the scope-diff violation detection is neutralized (violations stays [] / scope_diff_clean true).
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
