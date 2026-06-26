name: F06 · integration-gate.sh ff/conflict-not-clean — base-ref diverged from branch tip
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W/.bureau/regression" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  echo root > "$W/r.txt"; git -C "$W" add -A; git -C "$W" commit -qm root
  git -C "$W" branch base-branch
  git -C "$W" checkout -q base-branch; echo b > "$W/b.txt"; git -C "$W" add -A; git -C "$W" commit -qm base-advance
  git -C "$W" checkout -q "$(git -C "$W" rev-list --max-parents=0 HEAD)" 2>/dev/null || true
  git -C "$W" checkout -q -B work
  echo c > "$W/c.txt"; git -C "$W" add -A; git -C "$W" commit -qm branch-advance
  printf '{"scope":{}}\n' > "$TMP/state.json"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref base-branch \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$TMP/ctx"
  jq -e '.fast_forward_ok==false and (has("verdict")|not)' "$TMP/ctx/integration-results.json"
expected: exit 0 — base-branch is NOT an ancestor of the branch tip HEAD (they diverged), so merge-base --is-ancestor base-branch HEAD fails and fast_forward_ok==false; NO "verdict" key. Nonzero if the fast-forward check is forced true or the merge-base operand order is broken to a tautology.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
