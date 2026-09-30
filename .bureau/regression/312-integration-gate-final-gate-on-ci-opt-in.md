name: F312 · integration-gate.sh --final uses CI only when the PROJECT file declares ci_covers_full_suite, still runs its local-only gates, and runs local when state.json's copy diverges (issue #92)
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
  # pc <file> <json-block-or-empty>: a project-context.md with that integration_gate block.
  pc() {
    python3 - "$1" "$2" <<'PY'
  import sys
  path, block = sys.argv[1], sys.argv[2]
  text = "# Project Context\n\n## Git integration (execute / build runs)\n- **Integration branch:** `main`\n"
  if block:
      text += "\n## Integration gate (build runs)\n\n```json integration_gate\n" + block + "\n```\n"
  open(path, "w").write(text)
  PY
  }
  ON='{"cadence": "phase", "ci_covers_full_suite": true, "local_only_gates": [{"name": "docker smoke", "command": "sh docker-smoke.sh"}]}'
  OFF='{"cadence": "phase", "ci_covers_full_suite": false, "local_only_gates": []}'
  # The committed project file on the base branch opts in, with one local-only gate.
  pc "$W/project-context.md" "$ON"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q -b feat
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  GATED=$(git -C "$W" rev-parse HEAD)
  pc "$TMP/pc-off.md" "$OFF"
  pc "$TMP/pc-noblock.md" ""
  pc "$TMP/pc-bad.md" '{"ci_covers_full_suite": true, "local_only_gates": ["sh docker-smoke.sh"]}'
  # Fake gh: the PR head is the worktree HEAD and every check passed; pending when $FK/pending exists.
  printf '#!/bin/sh\ncase "$1 $2" in\n  "pr view") git -C "%s" rev-parse HEAD; exit 0 ;;\n  "pr checks")\n    b=pass; [ -f "%s/pending" ] && b=pending\n    echo "[{\\"name\\":\\"tests\\",\\"bucket\\":\\"$b\\",\\"state\\":\\"X\\",\\"workflow\\":\\"ci\\",\\"link\\":\\"\\"}]"; exit 0 ;;\nesac\nexit 1\n' "$W" "$FK" > "$BIN/gh"
  chmod +x "$BIN/gh"
  GIT='"git":{"pr_number":7,"github_repo":"o/r"}'
  printf '{"scope":{},%s}\n' "$GIT" > "$TMP/st-none.json"
  printf '{"scope":{},%s,"integration_gate":%s}\n' "$GIT" "$ON" > "$TMP/st-on.json"
  printf '{"scope":{},%s,"integration_gate":{"ci_covers_full_suite":true,"local_only_gates":[]}}\n' "$GIT" > "$TMP/st-short.json"
  printf '{"scope":{},%s,"integration_gate":{"ci_covers_full_suite":true}}\n' "$GIT" > "$TMP/st-flip.json"
  gate() {  # <case> <state> <extra args...>
    c="$1"; st="$2"; shift 2
    rm -f "$TMP/ran-full" "$TMP/ran-docker"; mkdir "$TMP/$c"
    PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$TMP/$st" --out "$TMP/$c" \
      --gate-mode ci --final --ci-poll 1 --ci-timeout 3 "$@" 2>/dev/null
  }
  local_with() {  # <case> <reason regex>: the full local suite ran, for that reason
    jq -e --arg re "$2" '.final_gate==true and .gate_mode=="local" and .gates[0].name=="regression"
      and (.gate_mode_reason|test($re))' "$TMP/$1/integration-results.json" >/dev/null \
      || { echo "FAIL $1"; jq -r .gate_mode_reason "$TMP/$1/integration-results.json"; exit 1; }
    [ -s "$TMP/ran-full" ] || { echo "FAIL $1: full local suite did not run"; exit 1; }
  }
  ci_with_docker() {  # <case>: CI decided, the local-only gate ran, the full suite did not
    jq -e '.final_gate==true and .gate_mode=="ci" and .canonical_source=="ci+local-only"
      and (.gate_mode_reason|test("^final gate on CI.*project-context.md.*docker smoke.*CI green on the exact head commit"))
      and ([.gates[].name]==["ci","docker smoke"])
      and (.gates[0].result=="green") and (.gates[1].result=="green" and .gates[1].local_only==true)
      and (.gate_commands|index("sh docker-smoke.sh"))!=null' "$TMP/$1/integration-results.json" >/dev/null \
      || { echo "FAIL $1"; jq -r .gate_mode_reason "$TMP/$1/integration-results.json"; exit 1; }
    [ ! -e "$TMP/ran-full" ] || { echo "FAIL $1: the full local suite ran despite the opt-in"; exit 1; }
    [ -s "$TMP/ran-docker" ] || { echo "FAIL $1: the local-only gate did not run"; exit 1; }
  }

  # A: the project file does not opt in => full local suite, reason names the missing opt-in.
  gate off st-none.json --project-context "$TMP/pc-off.md"
  local_with off '^final gate: the full local suite runs.*ci_covers_full_suite'
  # B: the base-ref project file opts in and state.json's copy matches => CI, local-only gate runs.
  gate on st-on.json
  ci_with_docker on
  grep -q "docker smoke ok" "$TMP/on/gate-output/docker_smoke.stdout.log"
  # B2: state.json carries no copy at all => the project file alone decides (still CI).
  gate nocopy st-none.json
  ci_with_docker nocopy
  # B3: the run branch deletes the local-only gate from its own project-context.md;
  # the gate reads the base-ref copy, so the local-only gate still runs.
  pc "$W/project-context.md" '{"ci_covers_full_suite": true, "local_only_gates": []}'
  git -C "$W" commit -qam "drop the docker gate"
  gate branchedit st-none.json
  ci_with_docker branchedit
  git -C "$W" reset -q --hard "$GATED"
  # C: opted in but still pending at the deadline => red, never green.
  touch "$FK/pending"
  gate pend st-on.json
  jq -e '.gate_mode=="ci" and .gates[0].result=="red" and .gates[0].exit_code_branch==124
    and .ci.status=="pending_timeout"' "$TMP/pend/integration-results.json" >/dev/null
  rm -f "$FK/pending"
  # F: state.json's copy is missing a local-only gate => divergence, full local suite.
  gate short st-short.json
  local_with short 'differs from the project file.*missing local-only gate\(s\): docker smoke'
  # G: state.json flips the opt-in on while the project file says off => divergence, local.
  gate flip st-flip.json --project-context "$TMP/pc-off.md"
  local_with flip 'differs from the project file.*ci_covers_full_suite is true in state.json but false'
  # H: state.json declares an opt-in but the project file has no block => local.
  gate noblock st-on.json --project-context "$TMP/pc-noblock.md"
  local_with noblock 'has no integration_gate block'
  # E: a malformed local-only list in the project file => local, not a silent skip.
  gate bad st-none.json --project-context "$TMP/pc-bad.md"
  local_with bad 'local_only_gates in .* is malformed'
  # D: opted in, but a merge from main since the last gate => full local suite.
  git -C "$W" checkout -q main; echo m > "$W/m.txt"; git -C "$W" add -A; git -C "$W" commit -qm main2
  git -C "$W" checkout -q feat; git -C "$W" merge -q --no-edit main
  gate merged st-on.json --since-ref "$GATED"
  local_with merged '^merge commit'
  echo PASS
expected: exit 0; stdout "PASS". The final gate reads ci_covers_full_suite and local_only_gates from the project file (the ```json integration_gate``` block of project-context.md as committed on --base-ref, or --project-context), never from state.json. A - a project file that does not opt in runs the full local suite. B - the base-ref file opts in and state.json matches: CI decides (gate_mode ci, canonical_source ci+local-only, a reason naming the project file and the local-only gate), the full suite does not run, and "docker smoke" runs locally, green, marked local_only, output kept. B2 - with no state.json copy the project file alone decides. B3 - the run branch deleting the local-only gate from its own project-context.md changes nothing (the base-ref copy is read). C - pending at the deadline is red (124). F - a state.json copy missing a local-only gate, G - a state.json copy that flips the opt-in on, and H - a state.json opt-in with no block in the project file each run the full local suite and say why. E - a malformed project list runs local. D - a merge since --since-ref runs local. MUTATION - reading the settings from state.json instead of the project file fails B3 and G; dropping the divergence check fails F and G; skipping the local-only run fails B.
phase: 92 · CI-gated integration checkpoints (final gate on CI)
owner: scripts/integration-gate.sh (final-gate opt-in from the project file + divergence check)
