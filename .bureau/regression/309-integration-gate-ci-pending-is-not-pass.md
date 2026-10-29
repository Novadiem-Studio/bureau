name: F309 · integration-gate.sh CI mode treats pending as a wait, never a pass - it waits for green, and records red at the deadline (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; FK="$TMP/fake"; BIN="$TMP/bin"
  mkdir -p "$W/.bureau/regression" "$FK" "$BIN"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\ntouch "%s/ran-local"\nexit 0\n' "$TMP" > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  git -C "$W" rev-parse HEAD > "$FK/head"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/state.json"
  # Fake gh: `pr checks` call n prints $FK/checks.n when it exists, else $FK/checks.
  export FK
  cat > "$BIN/gh" <<'SH'
  #!/bin/sh
  case "$1 $2" in
    "pr view") cat "$FK/head"; exit 0 ;;
    "pr checks")
      n=$(cat "$FK/count" 2>/dev/null || echo 0)
      n=$((n + 1)); echo "$n" > "$FK/count"
      if [ -f "$FK/delay" ]; then sleep "$(cat "$FK/delay")"; fi
      if [ -f "$FK/checks.$n" ]; then cat "$FK/checks.$n"; else cat "$FK/checks"; fi
      exit 8 ;;
  esac
  exit 1
  SH
  chmod +x "$BIN/gh"
  PASS_JSON='[{"name":"tests","bucket":"pass","state":"SUCCESS","workflow":"ci","link":""},{"name":"aggregate","bucket":"pass","state":"SUCCESS","workflow":"ci","link":""}]'
  PEND_JSON='[{"name":"tests","bucket":"pass","state":"SUCCESS","workflow":"ci","link":""},{"name":"aggregate","bucket":"pending","state":"IN_PROGRESS","workflow":"ci","link":""}]'
  FAIL_JSON='[{"name":"tests","bucket":"fail","state":"FAILURE","workflow":"ci","link":""},{"name":"aggregate","bucket":"pending","state":"IN_PROGRESS","workflow":"ci","link":""}]'
  gate() {
    mkdir "$TMP/$1"
    PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/$1" \
      --gate-mode ci --ci-poll 1 --ci-timeout "$2" 2>/dev/null
  }

  # Case A: the first check read itself outlasts the deadline. A slow host or gh
  # can legitimately use the whole budget in one poll; requiring >=2 was flaky.
  # Pending must still become red (124), with no fallback to the local suite.
  echo 3 > "$FK/delay"
  echo "$PEND_JSON" > "$FK/checks"
  gate a 2
  jq -e '.gate_mode=="ci" and .gates[0].result=="red" and .gates[0].exit_code_branch==124
    and .ci.status=="pending_timeout" and .ci.pending==["aggregate"] and .ci.polls==1
    and .ci.waited_s >= .ci.deadline_s
    and (.gate_mode_reason|test("pending is not a pass"))' "$TMP/a/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-local" ] || { echo "FAIL: a pending CI fell back to the local suite"; exit 1; }

  rm "$FK/delay"

  # Case B: pending on polls 1-2, green on poll 3 => the gate waited, then green.
  rm -f "$FK/count"; echo "$PEND_JSON" > "$FK/checks.1"; echo "$PEND_JSON" > "$FK/checks.2"
  echo "$PASS_JSON" > "$FK/checks"
  gate b 30
  jq -e '.gates[0].result=="green" and .gates[0].exit_code_branch==0 and .ci.status=="passed"
    and .ci.polls==3' "$TMP/b/integration-results.json" >/dev/null

  # Case C: one failed check with another still pending => red at once (exit 1), failure named.
  rm -f "$FK/count" "$FK/checks.1" "$FK/checks.2"; echo "$FAIL_JSON" > "$FK/checks"
  gate c 30
  jq -e '.gates[0].result=="red" and .gates[0].exit_code_branch==1 and .ci.status=="failed"
    and .ci.failed==["tests"] and .ci.polls==1' "$TMP/c/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-local" ]
  echo PASS
expected: exit 0; stdout "PASS". Case A - a deliberately slow first poll (3 s) still pending past a 2 s deadline gives a red gate (exit_code_branch 124, ci.status pending_timeout, ci.pending ["aggregate"], a reason saying pending is not a pass) after exactly one poll, waited_s reaches the deadline, and the local suite does not run in its place. Case B - pending on polls 1 and 2 and green on poll 3 gives a green gate after exactly 3 polls, so the gate waits rather than failing early. Case C - a failed check beside a pending one is red on the first poll (exit 1, ci.failed ["tests"]). MUTATION - classifying an unfinished check as passed (e.g. letting poll_once return "passed" whenever no check failed) turns Case A green; breaking out of the loop on "pending" turns Case B red.
phase: 92 · CI-gated integration checkpoints
owner: scripts/integration-gate.sh (CI poller: pending-is-not-pass)
