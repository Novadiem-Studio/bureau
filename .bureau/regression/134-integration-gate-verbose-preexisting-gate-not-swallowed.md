name: F08 · integration-gate.sh verbose claimed-pre-existing gate stdout does NOT contaminate PRE_EXISTING_JSON (pre_existing stays non-empty)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W/.bureau/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  # A CHATTY claimed-pre-existing gate: prints ~2KB non-JSON to stdout, then fails
  # (red) on BOTH base and branch (flaky.txt exists at base and is inherited). The
  # gate script is committed, so it exists at both base-ref and branch tip. Pre-fix,
  # the ret_branch/ret_base subprocess.run in the pre-existing loop had no
  # capture_output, so this blob inherited the python process's stdout — the
  # `$(...)` captured into PRE_EXISTING_JSON — crashing json.loads and collapsing
  # pre_existing to [] (a silent hole, with errors[] left empty).
  printf 'broken\n' > "$W/flaky.txt"
  printf '#!/bin/sh\nprintf "y%%.0s" $(seq 1 2000)\necho\nfor i in $(seq 1 40); do echo "pre-existing noise $i"; done\ntest ! -f flaky.txt\n' > "$W/chatty-gate.sh"
  chmod +x "$W/chatty-gate.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  printf '{"scope":{}}\n' > "$TMP/state.json"
  CLAIMED='[{"name":"chatty","command":"sh '"$W"'/chatty-gate.sh","result":"red","pre-existing":true}]'
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates "$CLAIMED" --state-json "$TMP/state.json" --out "$OUT"
  jq -e '(.pre_existing|length>0) and (any(.pre_existing[]; .name=="chatty" and .confirmed_pre_existing==true)) and (.errors==[]) and (has("verdict")|not)' "$OUT/integration-results.json"
expected: exit 0 — despite the chatty pre-existing gate printing ~2KB of non-JSON to stdout, capture_output=True on the SECOND subprocess.run site (the ret_branch/ret_base pre-existing loop) keeps that noise out of the PRE_EXISTING_JSON command-substitution, so pre_existing is NON-empty, records the chatty gate with confirmed_pre_existing==true, errors stays [], and there is NO "verdict" key. MUTATION — reverting `capture_output=True` on the pre-existing loop's ret_branch/ret_base subprocess.run makes the noisy gate contaminate the capture; json.loads then fails and pre_existing collapses to [] (with errors[] silently empty) → this fixture exits nonzero.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
