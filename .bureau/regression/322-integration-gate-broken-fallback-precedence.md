name: F322 · a valid worktree runner wins over a broken run-directory fallback (issue #117)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; RUN="$TMP/run"
  mkdir -p "$W/.bureau/regression" "$RUN/regression"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\necho "BUREAU-SUITE: primary executed"\nexit 0\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{}}\n' > "$RUN/state.json"
  for kind in directory dangling-link; do
    if [ "$kind" = directory ]; then
      mkdir "$RUN/regression/run.sh"
    else
      ln -s nowhere "$RUN/regression/run.sh"
    fi
    OUT="$TMP/$kind"; mkdir "$OUT"
    "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT"
    jq -e '.gates[] | select(.name=="regression")
      | .result=="green" and .exit_code_branch==0 and .runner_source=="worktree"
        and .suite=="primary executed" and (has("missing_reason")|not)' "$OUT/integration-results.json" >/dev/null
    if [ "$kind" = directory ]; then rmdir "$RUN/regression/run.sh"; else rm "$RUN/regression/run.sh"; fi
  done
  echo PASS
expected: exit 0; stdout "PASS". Both a directory and a dangling symlink at the lower-priority run-directory runner leave the valid worktree runner selected and executed. Its emitted suite marker proves execution. MUTATION - checking fallback breakage even when the worktree runner is a regular file makes the first case red/127 and fails the assertion.
phase: 117 · regression runner review fixes
owner: scripts/integration-gate.sh (runner precedence)
