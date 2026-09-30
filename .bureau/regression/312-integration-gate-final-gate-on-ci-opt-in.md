name: F312 · integration-gate.sh --final uses CI only when the project declares ci_covers_full_suite, still runs its local-only gates, and keeps the merge fallback (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; FK="$TMP/fake"; BIN="$TMP/bin"
  mkdir -p "$W/.bureau/regression" "$FK" "$BIN"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\necho full >> "%s/ran-full"\nexit 0\n' "$TMP" > "$W/.bureau/regression/run.sh"
  printf '#!/bin/sh\necho "docker smoke ok"\necho docker >> "%s/ran-docker"\nexit 0\n' "$TMP" > "$W/docker-smoke.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q -b feat
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  GATED=$(git -C "$W" rev-parse HEAD)
  # Fake gh: the PR head is the worktree HEAD and every check passed; pending when $FK/pending exists.
  printf '#!/bin/sh\ncase "$1 $2" in\n  "pr view") git -C "%s" rev-parse HEAD; exit 0 ;;\n  "pr checks")\n    b=pass; [ -f "%s/pending" ] && b=pending\n    echo "[{\\"name\\":\\"tests\\",\\"bucket\\":\\"$b\\",\\"state\\":\\"X\\",\\"workflow\\":\\"ci\\",\\"link\\":\\"\\"}]"; exit 0 ;;\nesac\nexit 1\n' "$W" "$FK" > "$BIN/gh"
  chmod +x "$BIN/gh"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/state-off.json"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"},"integration_gate":{"ci_covers_full_suite":true,"local_only_gates":[{"name":"docker smoke","command":"sh docker-smoke.sh"}]}}\n' > "$TMP/state-on.json"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"},"integration_gate":{"ci_covers_full_suite":true,"local_only_gates":["sh docker-smoke.sh"]}}\n' > "$TMP/state-bad.json"
  gate() {  # <case> <state> <extra args...>
    c="$1"; st="$2"; shift 2
    rm -f "$TMP/ran-full" "$TMP/ran-docker"; mkdir "$TMP/$c"
    PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$TMP/$st" --out "$TMP/$c" \
      --gate-mode ci --final --ci-poll 1 --ci-timeout 3 "$@" 2>/dev/null
  }

  # Case A: no opt-in => the final gate runs the full local suite, and says why.
  gate off state-off.json
  jq -e '.final_gate==true and .gate_mode=="local" and .gates[0].name=="regression"
    and (.gate_mode_reason|test("^final gate.*ci_covers_full_suite"))' "$TMP/off/integration-results.json" >/dev/null
  [ -s "$TMP/ran-full" ] || { echo "FAIL A: full local suite did not run"; exit 1; }

  # Case B: opt-in => CI decides on the exact head, the full local suite does not run,
  # and the local-only gate still runs here with its output kept.
  gate on state-on.json
  jq -e '.final_gate==true and .gate_mode=="ci" and .canonical_source=="ci+local-only"
    and (.gate_mode_reason|test("^final gate on CI.*docker smoke.*CI green on the exact head commit"))
    and ([.gates[].name]==["ci","docker smoke"])
    and (.gates[0].result=="green") and (.gates[1].result=="green" and .gates[1].local_only==true)
    and (.gate_commands|index("sh docker-smoke.sh"))!=null' "$TMP/on/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-full" ] || { echo "FAIL B: the full local suite ran despite the opt-in"; exit 1; }
  [ -s "$TMP/ran-docker" ] || { echo "FAIL B: the local-only gate did not run"; exit 1; }
  grep -q "docker smoke ok" "$TMP/on/gate-output/docker_smoke.stdout.log"

  # Case C: opt-in but CI still pending at the deadline => red, never green.
  touch "$FK/pending"
  gate pend state-on.json
  jq -e '.gate_mode=="ci" and .gates[0].result=="red" and .gates[0].exit_code_branch==124
    and .ci.status=="pending_timeout"' "$TMP/pend/integration-results.json" >/dev/null
  rm -f "$FK/pending"

  # Case D: opt-in, but a merge from main since the last gate => full local suite.
  git -C "$W" checkout -q main; echo m > "$W/m.txt"; git -C "$W" add -A; git -C "$W" commit -qm main2
  git -C "$W" checkout -q feat; git -C "$W" merge -q --no-edit main
  gate merged state-on.json --since-ref "$GATED"
  jq -e '.gate_mode=="local" and (.gate_mode_reason|test("^merge commit"))' "$TMP/merged/integration-results.json" >/dev/null
  [ -s "$TMP/ran-full" ]

  # Case E: a malformed local-only list => full local suite, not a silent skip.
  gate bad state-bad.json
  jq -e '.gate_mode=="local" and (.gate_mode_reason|test("local_only_gates is malformed"))' "$TMP/bad/integration-results.json" >/dev/null
  [ -s "$TMP/ran-full" ]
  echo PASS
expected: exit 0; stdout "PASS". A - without integration_gate.ci_covers_full_suite, `--gate-mode ci --final` runs the full local suite (final_gate true, gate_mode local, reason naming the missing opt-in). B - with the opt-in, CI green on the exact head decides the gate (gate_mode ci, canonical_source ci+local-only, reason starting "final gate on CI" and naming the local-only gate), the full local suite does not run, and the declared local-only gate "docker smoke" runs locally, green, marked local_only, with its output kept. C - opted in but still pending at the deadline is red (124, pending_timeout). D - opted in with a merge from main since --since-ref runs the full local suite. E - a malformed local_only_gates list runs the full local suite. MUTATION - making the final branch ignore the opt-in (always local) fails B; skipping the local-only run fails B's ran-docker check; accepting a malformed list silently fails E.
phase: 92 · CI-gated integration checkpoints (final gate on CI)
owner: scripts/integration-gate.sh (final-gate opt-in + local-only gates)
