name: F01 · integration-gate.sh Track-3 emits proceed-EVIDENCE field values (no verdict key)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W/.bureau/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  printf 'broken\n' > "$W/flaky.txt"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  mkdir -p "$W/src"
  for i in 1 2 3 4; do echo "c$i" > "$W/src/f$i.txt"; git -C "$W" add -A; git -C "$W" commit -qm "c$i"; done
  printf '{"scope":{"allowed_paths":["src/*",".bureau/*","flaky.txt"],"cut_symbols":[]}}\n' > "$TMP/state.json"
  CLAIMED='[{"name":"regression","command":"sh '"$W"'/.bureau/regression/run.sh","result":"green","pre-existing":false},{"name":"unit","command":"test ! -f flaky.txt","result":"red","pre-existing":true}]'
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates "$CLAIMED" --state-json "$TMP/state.json" --out "$OUT"
  jq -e '.escalate_marker=="" and (.gates|length>0) and (all(.gates[];.result=="green")) and (.pre_existing|length>0) and (all(.pre_existing[];.confirmed_pre_existing==true)) and (.scope.scope_diff_clean==true) and (.scope.violations==[]) and (.fast_forward_ok==true) and (.conflicts_clean==true) and (has("verdict")|not)' "$OUT/integration-results.json"
expected: exit 0 — the produced integration-results.json has escalate_marker=="" , every gates[].result=="green", every pre_existing[].confirmed_pre_existing==true, scope.scope_diff_clean==true, scope.violations==[], fast_forward_ok==true, conflicts_clean==true, and NO "verdict" key. Nonzero if any proceed-evidence field is wrong (e.g. the merge-base fast-forward operands are inverted) or a "verdict" key is added.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
