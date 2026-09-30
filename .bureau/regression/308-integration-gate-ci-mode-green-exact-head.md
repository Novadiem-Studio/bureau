name: F308 · integration-gate.sh CI mode passes only on CI green for the worktree's exact HEAD, and records the mode and command (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; FK="$TMP/fake"; BIN="$TMP/bin"
  mkdir -p "$W/.bureau/regression" "$FK" "$BIN"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # The local runner leaves a marker, so the fixture can prove CI mode did NOT run it.
  printf '#!/bin/sh\ntouch "%s/ran-local"\nexit 0\n' "$TMP" > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  HEAD_SHA=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/state.json"
  # Fake gh: `pr view` prints $FK/head, `pr checks` prints $FK/checks.
  printf '#!/bin/sh\ncase "$1 $2" in\n  "pr view") cat "%s/head"; exit 0 ;;\n  "pr checks") echo "$*" >> "%s/argv"; cat "%s/checks"; exit 0 ;;\nesac\nexit 1\n' "$FK" "$FK" "$FK" > "$BIN/gh"
  chmod +x "$BIN/gh"
  printf '[{"name":"tests (1/2)","bucket":"pass","state":"SUCCESS","workflow":"ci","link":""},{"name":"tests (2/2)","bucket":"pass","state":"SUCCESS","workflow":"ci","link":""},{"name":"lint","bucket":"skipping","state":"SKIPPED","workflow":"ci","link":""}]\n' > "$FK/checks"

  # Case A: PR head == worktree HEAD, every check passed or skipped => green, CI decided it.
  echo "$HEAD_SHA" > "$FK/head"
  mkdir "$TMP/a"
  PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/a" \
    --gate-mode ci --ci-poll 1 --ci-timeout 5 2>/dev/null
  jq -e --arg h "$HEAD_SHA" '.gate_mode=="ci" and .gate_mode_requested=="ci"
    and (.gates|length)==1 and .gates[0].name=="ci" and .gates[0].result=="green"
    and .gates[0].exit_code_branch==0 and .gates[0].head_sha==$h
    and .ci.status=="passed" and .ci.pr=="7" and .ci.repo=="o/r" and .ci.head_sha==$h
    and (.gate_commands|length)==1 and (.gate_commands[0]|startswith("gh pr checks 7 -R o/r"))
    and .canonical_source=="ci" and .under_declaration==[] and .escalate_marker==""
    and .fast_forward_ok==true and (has("verdict")|not)' "$TMP/a/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-local" ] || { echo "FAIL: CI mode ran the local suite"; exit 1; }
  [ -s "$TMP/a/gate-output/ci-poll.log" ] && [ -s "$TMP/a/gate-output/ci-checks.json" ]
  grep -q -- "-R o/r" "$FK/argv"

  # Case B: PR head is some other commit (the branch tip was never pushed) => never green.
  echo "$BASE" > "$FK/head"
  mkdir "$TMP/b"
  PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/b" \
    --gate-mode ci --ci-poll 1 --ci-timeout 2 2>/dev/null
  jq -e '.gate_mode=="ci" and .gates[0].result=="red" and .gates[0].exit_code_branch==124
    and .ci.status=="head_mismatch_timeout"' "$TMP/b/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-local" ]
  echo PASS
expected: exit 0; stdout "PASS". Case A - with the fake PR head equal to the worktree HEAD and every check pass/skipping, integration-results.json has gate_mode "ci" (requested "ci"), exactly one gate named "ci" that is green with exit_code_branch 0 and head_sha = HEAD, ci.status "passed" with pr/repo read from state.json#git, gate_commands naming `gh pr checks 7 -R o/r`, canonical_source "ci", empty under_declaration, the kept ci-poll.log and ci-checks.json, and the local runner never ran. Case B - with the PR head on a different commit the gate is red (exit_code_branch 124, ci.status head_mismatch_timeout), never green. MUTATION - dropping the `h1 != local_sha` head check in poll_once (scripts/integration-gate.sh) makes Case B read green; making EFFECTIVE_MODE ignore "ci" runs the local suite and fails the ran-local check.
phase: 92 · CI-gated integration checkpoints
owner: scripts/integration-gate.sh (gate-mode resolution + CI poller)
