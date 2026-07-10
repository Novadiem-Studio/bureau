name: F05 · integration-gate.sh verbose gate stdout does NOT contaminate the JSON capture (gates stays non-empty)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W/.bureau/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # The canonical regression runner is a CHATTY green gate: it prints a large
  # NON-JSON blob (2000 x's + newlines) to stdout, then exits 0. Pre-fix, that
  # blob inherited the gate-runner python process's stdout — the very `$(...)`
  # the shell captures into GATE_RESULTS_JSON — prepending non-JSON, crashing
  # the downstream json.loads, and collapsing gates to [] (a silent all-clear).
  printf '#!/bin/sh\nprintf "x%%.0s" $(seq 1 2000)\necho\nfor i in $(seq 1 40); do echo "PASS line $i"; done\nexit 0\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '(.gates|length>0) and (any(.gates[]; .name=="regression" and .result=="green" and .exit_code_branch==0)) and .escalate_marker=="" and (has("verdict")|not)' "$OUT/integration-results.json"
expected: exit 0 — despite the chatty green gate printing ~2KB of non-JSON to stdout, capture_output=True keeps that noise out of the command-substitution, so gates is NON-empty and records the regression gate with result=="green"/exit_code_branch==0; escalate_marker=="" and NO "verdict" key. MUTATION — reverting `capture_output=True` on the canonical-gate subprocess.run (scripts/integration-gate.sh, the "RUN EACH CANONICAL GATE" loop) makes the noisy gate contaminate the capture; json.loads then fails and gates collapses to [] → this fixture exits nonzero.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
