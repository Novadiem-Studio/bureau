name: F314 · integration-gate.sh runs RUN_DIR/regression/run.sh when the target repo has no committed runner, and the committed runner wins when both exist (issue #115)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  # A target repo with NO .bureau/ at all (the client-team-repo case), and a run
  # dir holding the run's own runner next to state.json.
  W="$TMP/wt"; RUN="$TMP/run dir"; OUT="$TMP/ctx"; mkdir -p "$W" "$RUN/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo base > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  # The run-dir runner proves it ran with the worktree as cwd.
  printf '#!/bin/sh\necho "BUREAU-SUITE: run-dir fixtures"\ntest -f f.txt\n' > "$RUN/regression/run.sh"
  printf '{"scope":{}}\n' > "$RUN/state.json"
  # (a) RUN_DIR defaults to the directory holding --state-json.
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[{"name":"regression","command":"x","result":"green"}]' \
    --state-json "$RUN/state.json" --out "$OUT" 2>/dev/null
  jq -e --arg p "$RUN/regression/run.sh" '.gates[] | select(.name=="regression")
    | .result=="green" and .exit_code_branch==0 and .runner_source=="run-dir"
      and .runner_path==$p and .suite=="run-dir fixtures"' "$OUT/integration-results.json" >/dev/null
  jq -e '.canonical_source=="regression-only" and (.gate_commands|length)==1' "$OUT/integration-results.json" >/dev/null
  # (b) An explicit --run-dir is honoured when state.json lives elsewhere.
  OUT2="$TMP/ctx2"; mkdir -p "$OUT2"; printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --run-dir "$RUN" --out "$OUT2" 2>/dev/null
  jq -e '.gates[] | select(.name=="regression") | .result=="green" and .runner_source=="run-dir"' "$OUT2/integration-results.json" >/dev/null
  # (c) With a committed runner too, the worktree runner is the one that runs.
  mkdir -p "$W/.bureau/regression"; printf '#!/bin/sh\nexit 3\n' > "$W/.bureau/regression/run.sh"
  OUT3="$TMP/ctx3"; mkdir -p "$OUT3"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT3" 2>/dev/null
  jq -e '.gates[] | select(.name=="regression") | .result=="red" and .exit_code_branch==3 and .runner_source=="worktree"' "$OUT3/integration-results.json" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". With no .bureau/ in the target repo and a runner at RUN_DIR/regression/run.sh (RUN_DIR taken from the --state-json directory, or from --run-dir), the regression gate runs that runner from the worktree, is green, and records runner_source "run-dir" and its runner_path; a path with a space is quoted. When the worktree also has .bureau/regression/run.sh, that one runs instead (runner_source "worktree"). MUTATION - reverting the canonical gate to the hardcoded "sh <worktree>/.bureau/regression/run.sh" makes (a) red with exit 127, so the fixture fails; dropping the --state-json dirname default fails (a); swapping the search order fails (c).
phase: 115 · integration gate regression runner resolution
owner: scripts/integration-gate.sh (regression runner resolution)
