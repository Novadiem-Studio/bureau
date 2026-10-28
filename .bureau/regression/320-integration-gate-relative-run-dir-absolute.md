name: F320 · integration-gate.sh resolves a relative --state-json run dir to an absolute runner path before running it from the worktree (issue #115)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  # Physical path: the gate's cwd-based abspath resolves macOS /var -> /private/var.
  TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W" "$TMP/run/regression" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo base > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf '#!/bin/sh\nexit 0\n' > "$TMP/run/regression/run.sh"
  printf '{"scope":{}}\n' > "$TMP/run/state.json"
  # A file at the same relative path inside the worktree must not be what runs.
  mkdir -p "$W/run/regression"; printf '#!/bin/sh\nexit 9\n' > "$W/run/regression/run.sh"
  (cd "$TMP" && "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json run/state.json --out "$TMP/ctx" 2>/dev/null)
  jq -e --arg p "$TMP/run/regression/run.sh" '.gates[] | select(.name=="regression")
    | .result=="green" and .exit_code_branch==0 and .runner_source=="run-dir" and .runner_path==$p' \
    "$TMP/ctx/integration-results.json" >/dev/null
  echo PASS
expected: exit 0; stdout "PASS". Called from another directory with --state-json run/state.json, the gate resolves the run dir to its absolute path, so the runner it checks, hashes and records is the one it runs (green, runner_path absolute), not a same-named file inside the worktree. MUTATION - dropping the os.path.abspath() on the run dir runs worktree/run/regression/run.sh (exit 9, red), so the fixture fails.
phase: 115 · integration gate regression runner resolution
owner: scripts/integration-gate.sh (runner path resolution)
