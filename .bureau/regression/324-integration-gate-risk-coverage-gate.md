name: integration-gate.sh adds a risk-coverage gate for bureau-lite runs only
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; R="$TMP/run"; mkdir -p "$W/.bureau/regression" "$R/risk-tags" "$TMP/ctx1" "$TMP/ctx2"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD); git -C "$W" checkout -q -b run
  echo 'x = 1' > "$W/f.py"; git -C "$W" add -A; git -C "$W" commit -qm unscanned
  : > "$R/log.md"
  # bureau-lite run with an unscanned commit: the gate records a red risk-coverage gate
  printf '{"workflow":"bureau-lite","workflow_shifts":[],"scope":{},"git":{"base_sha":"%s","base_branch":"main","worktree_path":"%s"}}\n' "$BASE" "$W" > "$R/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$R/state.json" --out "$TMP/ctx1" >/dev/null 2>&1 || true
  jq -e 'any(.gates[]; .name=="risk-coverage" and .result=="red" and (.problems|length>0))' "$TMP/ctx1/integration-results.json" >/dev/null \
    || { echo "FAIL: no red risk-coverage gate"; cat "$TMP/ctx1/integration-results.json"; exit 1; }
  [ -f "$TMP/ctx1/risk-coverage.json" ] || { echo "FAIL: no risk-coverage.json in the gate context"; exit 1; }
  # a feature run gets no risk-coverage gate at all
  printf '{"workflow":"feature","workflow_shifts":[],"scope":{}}\n' > "$R/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$R/state.json" --out "$TMP/ctx2" >/dev/null 2>&1 || true
  jq -e '(.gates|length>0) and all(.gates[]; .name!="risk-coverage")' "$TMP/ctx2/integration-results.json" >/dev/null \
    || { echo "FAIL: risk-coverage gate on a feature run"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. For a bureau-lite state.json with a commit in no risk-tags record, integration-gate.sh's integration-results.json carries a red `risk-coverage` gate with its problems and writes risk-coverage.json into --out; for a feature run no such gate appears and the ordinary gates are unchanged. MUTATION — deleting the BUREAU-LITE COVERAGE GATE block in scripts/integration-gate.sh makes the first assertion fail.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/integration-gate.sh
