name: F323 · only tracked fixtures trigger the missing-worktree-runner guard (issue #117)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; RUN="$TMP/run"
  mkdir -p "$W/.bureau/regression" "$RUN/regression"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '.bureau/regression/02-ignored.md\n' > "$W/.gitignore"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{}}\n' > "$RUN/state.json"
  printf 'name: untracked\n' > "$W/.bureau/regression/01-untracked.md"
  printf 'name: ignored\n' > "$W/.bureau/regression/02-ignored.md"
  printf '#!/bin/sh\necho "BUREAU-SUITE: fallback executed"\nexit 0\n' > "$RUN/regression/run.sh"
  gate() {
    OUT="$TMP/$1"; mkdir "$OUT"
    "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT"
    R="$OUT/integration-results.json"
  }
  gate fallback
  jq -e '.gates[] | select(.name=="regression")
    | .result=="green" and .exit_code_branch==0 and .runner_source=="run-dir"
      and .suite=="fallback executed"' "$R" >/dev/null
  rm "$RUN/regression/run.sh"
  gate absent
  jq -e '.gates[] | select(.name=="regression")
    | .result=="absent" and .exit_code_branch==null and .fixtures_found==2' "$R" >/dev/null
  git -C "$W" add .bureau/regression/01-untracked.md; git -C "$W" commit -qm fixture
  printf '#!/bin/sh\nexit 0\n' > "$RUN/regression/run.sh"
  gate tracked
  jq -e '.gates[] | select(.name=="regression")
    | .result=="red" and .exit_code_branch==127 and .runner_source=="missing"
      and (.missing_reason|contains("no run.sh beside them"))' "$R" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". Untracked and ignored fixtures allow a valid run-directory runner to execute, or an absent result when no runner exists. Committing the fixture still triggers red/127 even with a valid fallback. MUTATION - replacing the tracked-fixture check with the filesystem glob fails the fallback assertion; removing the fixture guard entirely fails the tracked assertion.
phase: 117 · regression runner review fixes
owner: scripts/integration-gate.sh (tracked fixture guard)
