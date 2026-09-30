name: F310 · integration-gate.sh CI mode runs the full local suite, with the reason recorded, for a final gate, after a merge, with no PR, and with no CI (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; FK="$TMP/fake"; BIN="$TMP/bin"
  mkdir -p "$W/.bureau/regression" "$FK" "$BIN"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\necho local >> "%s/ran-local"\nexit 0\n' "$TMP" > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q -b feat
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  GATED=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/state.json"
  printf '{"scope":{},"git":{"pr_number":null}}\n' > "$TMP/state-nopr.json"
  # Fake gh: a green PR on HEAD, unless $FK/nochecks exists.
  printf '#!/bin/sh\ncase "$1 $2" in\n  "pr view") git -C "%s" rev-parse HEAD; exit 0 ;;\n  "pr checks")\n    if [ -f "%s/nochecks" ]; then echo "no checks reported on the feat branch" >&2; exit 1; fi\n    echo "[{\\"name\\":\\"tests\\",\\"bucket\\":\\"pass\\",\\"state\\":\\"SUCCESS\\",\\"workflow\\":\\"ci\\",\\"link\\":\\"\\"}]"; exit 0 ;;\nesac\nexit 1\n' "$W" "$FK" > "$BIN/gh"
  chmod +x "$BIN/gh"
  # run <case> <reason-regex> <gate args...>: expect a local run with that reason.
  run() {
    c="$1"; re="$2"; shift 2
    rm -f "$TMP/ran-local"; mkdir "$TMP/$c"
    PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --out "$TMP/$c" --ci-poll 1 --ci-timeout 5 "$@" 2>/dev/null
    jq -e --arg re "$re" '.gate_mode=="local" and .ci==null
      and .gates[0].name=="regression" and .gates[0].result=="green"
      and (.gate_commands[0]|test("regression/run.sh"))
      and (.gate_mode_reason|test($re))' "$TMP/$c/integration-results.json" >/dev/null \
      || { echo "FAIL case $c"; jq '{gate_mode,gate_mode_requested,gate_mode_reason}' "$TMP/$c/integration-results.json"; exit 1; }
    [ -s "$TMP/ran-local" ] || { echo "FAIL case $c: local suite did not run"; exit 1; }
  }

  # Sanity: this PR is green, so plain CI mode does not run the local suite.
  mkdir "$TMP/ci"
  PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ci" --gate-mode ci --ci-poll 1 2>/dev/null
  jq -e '.gate_mode=="ci" and .gates[0].result=="green"' "$TMP/ci/integration-results.json" >/dev/null
  [ ! -e "$TMP/ran-local" ]

  # The default mode is local and says so.
  run default '^local mode requested$' --state-json "$TMP/state.json"
  jq -e '.gate_mode_requested=="local"' "$TMP/default/integration-results.json" >/dev/null
  # A final gate always runs local.
  run final '^final gate' --state-json "$TMP/state.json" --gate-mode ci --final
  # No PR known (none passed, state.json has none).
  run nopr '^no pull request known' --state-json "$TMP/state-nopr.json" --gate-mode ci
  # No checks on the head commit after the grace period.
  touch "$FK/nochecks"
  run nochecks '^no CI on ' --state-json "$TMP/state.json" --gate-mode ci --ci-no-checks-grace 0
  rm -f "$FK/nochecks"
  # A merge of main since the last gated commit forces local (first gate after a merge).
  git -C "$W" checkout -q main; echo m > "$W/m.txt"; git -C "$W" add -A; git -C "$W" commit -qm main2
  git -C "$W" checkout -q feat; git -C "$W" merge -q --no-edit main
  run merged '^merge commit\(s\) since the last gate' --state-json "$TMP/state.json" --gate-mode ci --since-ref "$GATED"
  jq -e '.gate_mode_requested=="ci"' "$TMP/merged/integration-results.json" >/dev/null
  # An unresolvable since-ref cannot rule a merge out, so local too.
  run badref 'not resolvable' --state-json "$TMP/state.json" --gate-mode ci --since-ref no-such-ref
  echo PASS
expected: exit 0; stdout "PASS". With a PR that is green on HEAD, plain `--gate-mode ci` does not run the local suite. Each of these then runs the local regression runner and records gate_mode "local", ci null, a green "regression" gate, gate_commands naming the runner, and a gate_mode_reason naming why - the default mode ("local mode requested", gate_mode_requested "local"), `--final` ("final gate ..."), no PR in flags or state.json ("no pull request known ..."), gh reporting no checks after the grace period ("no CI on ..."), a merge commit in --since-ref..HEAD ("merge commit(s) since the last gate ...", gate_mode_requested still "ci"), and an unresolvable --since-ref ("... not resolvable ..."). MUTATION - deleting the `if final == "1"` branch, the merge-since check, or the no_checks fallback in the gate-mode resolver (scripts/integration-gate.sh) leaves that case in CI mode, so its local-run check fails.
phase: 92 · CI-gated integration checkpoints
owner: scripts/integration-gate.sh (gate-mode resolution: local-required cases)
