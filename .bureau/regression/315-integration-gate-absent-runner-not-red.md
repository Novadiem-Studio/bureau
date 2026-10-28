name: F315 · integration-gate.sh records a regression gate with no runner anywhere as absent, never red or exit 127 (issue #115)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; RUN="$TMP/run"; OUT="$TMP/ctx"; mkdir -p "$W" "$RUN/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo base > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  # Markdown fixtures in the run dir but no run.sh: the incident shape.
  printf 'name: a\n' > "$RUN/regression/01-a.md"; printf 'name: b\n' > "$RUN/regression/02-b.md"
  printf '{"scope":{}}\n' > "$RUN/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT" 2>/dev/null
  R="$OUT/integration-results.json"
  jq -e --arg w "$W/.bureau/regression/run.sh" --arg r "$RUN/regression/run.sh" '
    (.gates | length)==1
    and (.gates[0] | .name=="regression" and .result=="absent" and .exit_code_branch==null
         and .runner_source=="absent" and .runner_searched==[$w,$r] and .fixtures_found==2)
    and .canonical_source=="regression-absent"
    and .gate_commands==[]
    and ([.gates[] | select(.result=="red")] | length)==0' "$R" >/dev/null
  # No gate-output log was written for a gate that never ran.
  test ! -e "$OUT/gate-output/regression.stdout.log"
  # Manifest gates still run beside an absent regression gate.
  printf '{"scripts":{"test":"true"}}\n' > "$W/package.json"
  git -C "$W" add -A; git -C "$W" commit -qm manifest
  OUT2="$TMP/ctx2"; mkdir -p "$OUT2"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT2" 2>/dev/null
  jq -e '.canonical_source=="manifest-only"
    and (.gates[] | select(.name=="regression") | .result=="absent")
    and (.gates[] | select(.name=="npm-test") | .result=="green")
    and .gate_commands==["npm run test"]' "$OUT2/integration-results.json" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". With no runner at <worktree>/.bureau/regression/run.sh or RUN_DIR/regression/run.sh, the regression gate is recorded result "absent", exit_code_branch null, runner_source "absent", runner_searched listing both paths in order, fixtures_found 2 (the NN-*.md files in RUN_DIR/regression), canonical_source "regression-absent", and it is left out of gate_commands; no gate ran, so no gate-output log exists and no gate is red. A package.json test script still runs green beside it and canonical_source becomes "manifest-only". MUTATION - removing the absent branch in run_gates runs the "(absent)" command, which exits 127 and records red, so the fixture fails; so does keeping the old hardcoded worktree runner.
phase: 115 · integration gate regression runner resolution
owner: scripts/integration-gate.sh (absent regression gate)
