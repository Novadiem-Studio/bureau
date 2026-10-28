name: F321 · integration-gate.sh carries the known-flaky flag into under_declaration and pre_existing, and never demotes a missing runner (issue #115)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W/.bureau/regression" "$TMP/ctx" "$TMP/ctx2"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # A red regression runner, and a claimed gate that passes at base but fails on the branch.
  printf '#!/bin/sh\nexit 1\n' > "$W/.bureau/regression/run.sh"
  printf '#!/bin/sh\nexit 0\n' > "$W/flaky.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base; BASE=$(git -C "$W" rev-parse HEAD)
  printf '#!/bin/sh\nexit 1\n' > "$W/flaky.sh"; git -C "$W" add -A; git -C "$W" commit -qm c1
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[{"name":"wobbly","command":"sh flaky.sh","result":"red","pre-existing":true}]' \
    --known-flaky-gates '[{"name":"regression"},{"name":"wobbly"}]' \
    --state-json "$TMP/state.json" --out "$TMP/ctx" 2>/dev/null
  R="$TMP/ctx/integration-results.json"
  # The undeclared red regression gate is flagged in gates[] AND in under_declaration[].
  jq -e '(.gates[] | select(.name=="regression") | .result=="red" and .flaky==true)
    and (.under_declaration[] | select(.name=="regression") | .result=="red" and .flaky==true)' "$R" >/dev/null
  # The claimed pre-existing red that passes at base is flagged in pre_existing[].
  jq -e '.pre_existing[] | select(.name=="wobbly")
    | .confirmed_pre_existing==false and .exit_code_branch==1 and .flaky==true' "$R" >/dev/null
  # A runner the branch deleted is red and NOT demoted, even when "regression" is listed flaky.
  git -C "$W" rm -q .bureau/regression/run.sh; git -C "$W" commit -qm "drop runner"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --known-flaky-gates '[{"name":"regression"}]' \
    --state-json "$TMP/state.json" --out "$TMP/ctx2" 2>/dev/null
  jq -e '(.gates[] | select(.name=="regression") | .runner_source=="missing" and (has("flaky")|not))
    and (.under_declaration[] | select(.name=="regression") | has("flaky")|not)' "$TMP/ctx2/integration-results.json" >/dev/null
  # The verifying checklist demotes a flaky red in under_declaration and pre_existing too.
  DM="$ROOT/agents/delegate.md"
  PATH=/usr/bin:$PATH grep -q 'known-flaky gate <name> failed and was not declared' "$DM" \
    || { echo "FAIL: delegate.md under-declaration flaky demotion missing"; exit 1; }
  PATH=/usr/bin:$PATH grep -q 'carries `flaky: true` (named in known-flaky-gates)' "$DM" \
    || { echo "FAIL: delegate.md pre-existing flaky demotion missing"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". With "regression" and "wobbly" in --known-flaky-gates, the undeclared red regression gate carries flaky true in both gates[] and under_declaration[], and the claimed pre-existing "wobbly" gate (green at base, red on the branch) carries flaky true in pre_existing[]. A regression gate that is red because the branch deleted its runner (runner_source "missing") gets no flaky flag anywhere. MUTATION - applying the demotion to GATE_RESULTS_JSON only (the pre-#115 block) leaves under_declaration[] and pre_existing[] unflagged, so the cold reviewer escalates a declared-flaky gate and the fixture fails; dropping the missing_reason exclusion flags the deleted runner flaky and fails the last assertion.
phase: 115 · integration gate regression runner resolution
owner: scripts/integration-gate.sh (known-flaky demotion)
