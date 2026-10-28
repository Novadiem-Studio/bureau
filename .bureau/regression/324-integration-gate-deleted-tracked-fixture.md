name: F324 · tracked fixtures missing from disk still require a worktree runner (PR #118 review)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; RUN="$TMP/run"
  mkdir -p "$W/.bureau/regression" "$RUN/regression"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf 'name: tracked\n' > "$W/.bureau/regression/01-tracked.md"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  rm "$W/.bureau/regression/01-tracked.md"
  printf '{"scope":{}}\n' > "$RUN/state.json"
  printf '#!/bin/sh\ntouch fallback-ran\n' > "$RUN/regression/run.sh"
  for kind in fallback absent; do
    OUT="$TMP/$kind"; mkdir "$OUT"
    "$ROOT/scripts/integration-gate.sh" --checkpoint-type integration --worktree-path "$W" \
      --base-ref "$BASE" --claimed-gates '[]' --state-json "$RUN/state.json" --out "$OUT"
    jq -e '.gates[] | select(.name=="regression")
      | .result=="red" and .exit_code_branch==127 and .runner_source=="missing"
        and (.missing_reason|contains("no run.sh beside them"))' "$OUT/integration-results.json" >/dev/null
    test ! -e "$W/fallback-ran"
    if [ "$kind" = fallback ]; then rm "$RUN/regression/run.sh"; fi
  done
  echo PASS
expected: exit 0; stdout "PASS". An unstaged deletion of a committed fixture does not hide the tracked suite: regression stays red/127 with and without a fallback runner, and the fallback never executes. MUTATION - intersecting tracked paths with filesystem glob matches makes the first case green and fails the assertion.
phase: 117 · PR 118 review fixes
owner: scripts/integration-gate.sh (tracked fixture guard)
