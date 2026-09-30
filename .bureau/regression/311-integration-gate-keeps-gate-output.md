name: F311 · integration-gate.sh keeps every gate's stdout and stderr in the checkpoint dir, and names the runner digest and suite (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W/.bureau/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # A red runner: names its suite, prints to both streams, exits 2 (the 1a4a-2 cp 11 shape).
  printf '#!/bin/sh\necho "BUREAU-SUITE: make test-fast"\nfor i in 1 2 3; do echo "collected line $i"; done\necho "E   setup failed: cluster refused" >&2\nexit 2\n' > "$W/.bureau/regression/run.sh"
  printf '#!/bin/sh\necho "claimed gate output"\necho "claimed gate stderr" >&2\nexit 1\n' > "$W/claimed.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[{"name":"claimed unit","command":"sh claimed.sh","result":"red","pre-existing":true}]' \
    --state-json "$TMP/state.json" --out "$OUT" 2>/dev/null
  R="$OUT/integration-results.json"
  RUNNER_SHA=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$W/.bureau/regression/run.sh")
  jq -e --arg sha "$RUNNER_SHA" '.gate_mode=="local"
    and (.gates[] | select(.name=="regression")
      | .result=="red" and .exit_code_branch==2
      and .stdout_path=="gate-output/regression.stdout.log"
      and .stderr_path=="gate-output/regression.stderr.log"
      and (.stdout_tail|index("collected line 3")) != null
      and (.stderr_tail|index("E   setup failed: cluster refused")) != null
      and .suite=="make test-fast" and .runner_sha256==$sha)' "$R" >/dev/null
  grep -q "collected line 2" "$OUT/gate-output/regression.stdout.log"
  grep -q "cluster refused" "$OUT/gate-output/regression.stderr.log"
  # The pre-existing re-run keeps its output too, on both sides.
  jq -e '.pre_existing[0].output_paths.branch[0]=="gate-output/pre-existing-claimed_unit.branch.stdout.log"' "$R" >/dev/null
  grep -q "claimed gate output" "$OUT/gate-output/pre-existing-claimed_unit.branch.stdout.log"
  grep -q "claimed gate stderr" "$OUT/gate-output/pre-existing-claimed_unit.base.stderr.log"
  # The JSON capture is still clean (verbose gates cannot contaminate it).
  jq -e '(.gates|length)>0 and (has("verdict")|not)' "$R" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". A red regression runner (exit 2) that prints to stdout and stderr leaves gate-output/regression.stdout.log and .stderr.log in the --out dir with that text, and its gate record carries result red, exit_code_branch 2, both paths, a stdout_tail and stderr_tail holding the last lines, suite "make test-fast" from its BUREAU-SUITE line, and runner_sha256 equal to the runner file's digest. A claimed pre-existing red gate's branch and base re-runs keep their output under gate-output/pre-existing-<name>.{branch,base}.{stdout,stderr}.log. MUTATION - sending the canonical gate's streams back to capture_output=True (the pre-#92 behaviour) leaves no kept files and no tails, so the fixture fails; so does dropping the BUREAU-SUITE extraction or the runner digest.
phase: 92 · CI-gated integration checkpoints
owner: scripts/integration-gate.sh (kept gate output)
