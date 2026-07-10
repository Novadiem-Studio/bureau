name: F06 · integration-gate.sh conflicts_clean is a merge test, not working-tree cleanliness (untracked file ≠ conflict; ff-ok ⇒ conflicts-clean)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

  # ── CASE A: fast-forwardable (base IS an ancestor of HEAD) WITH an untracked
  # working-tree file present (mimics the Delegate's own untracked
  # .bureau/regression/run.sh). conflicts_clean MUST be true — an untracked file
  # is NOT a merge conflict — and must NOT contradict fast_forward_ok==true.
  WA="$TMP/wtA"; OUTA="$TMP/ctxA"; mkdir -p "$WA/.bureau/regression" "$OUTA"
  git -C "$WA" init -q; git -C "$WA" config user.email t@t; git -C "$WA" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$WA/.bureau/regression/run.sh"
  git -C "$WA" add -A; git -C "$WA" commit -qm base
  BASEA=$(git -C "$WA" rev-parse HEAD)
  echo c1 > "$WA/f.txt"; git -C "$WA" add -A; git -C "$WA" commit -qm c1   # HEAD ahead of BASE ⇒ ff-able
  printf 'untracked\n' > "$WA/untracked.txt"                              # Delegate's own untracked file
  printf '{"scope":{}}\n' > "$TMP/stateA.json"
  "$GATE" --checkpoint-type integration --worktree-path "$WA" --base-ref "$BASEA" \
    --claimed-gates '[]' --state-json "$TMP/stateA.json" --out "$OUTA"
  jq -e '.fast_forward_ok==true and .conflicts_clean==true and (.fast_forward_ok==true and .conflicts_clean==true) and (has("verdict")|not)' "$OUTA/integration-results.json"

  # ── CASE B: genuinely-conflicting, non-ff branch. base advanced a line one way,
  # HEAD advanced the SAME line the other way, off a common ancestor ⇒ a real
  # 3-way merge conflict. conflicts_clean MUST be false (and fast_forward_ok
  # false — base is not an ancestor of HEAD).
  WB="$TMP/wtB"; OUTB="$TMP/ctxB"; mkdir -p "$WB/.bureau/regression" "$OUTB"
  git -C "$WB" init -q; git -C "$WB" config user.email t@t; git -C "$WB" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$WB/.bureau/regression/run.sh"
  printf 'line-original\n' > "$WB/conflict.txt"
  git -C "$WB" add -A; git -C "$WB" commit -qm base
  ANCESTOR=$(git -C "$WB" rev-parse HEAD)
  printf 'line-from-BASE-side\n' > "$WB/conflict.txt"; git -C "$WB" add -A; git -C "$WB" commit -qm base-advance
  BASEB=$(git -C "$WB" rev-parse HEAD)
  git -C "$WB" checkout -q -b feat "$ANCESTOR"
  printf 'line-from-HEAD-side\n' > "$WB/conflict.txt"; git -C "$WB" add -A; git -C "$WB" commit -qm head-advance
  printf '{"scope":{}}\n' > "$TMP/stateB.json"
  "$GATE" --checkpoint-type integration --worktree-path "$WB" --base-ref "$BASEB" \
    --claimed-gates '[]' --state-json "$TMP/stateB.json" --out "$OUTB"
  jq -e '.fast_forward_ok==false and .conflicts_clean==false and (has("verdict")|not)' "$OUTB/integration-results.json"
expected: exit 0 — CASE A (ff-able + untracked file) yields fast_forward_ok==true AND conflicts_clean==true (the untracked file is not a conflict, and the two fields never contradict); CASE B (a real same-line 3-way conflict, non-ff) yields fast_forward_ok==false AND conflicts_clean==false. Neither has a "verdict" key. MUTATION — reverting conflicts_clean to the old `git status --porcelain` test fails CASE A: the untracked file makes the tree dirty → conflicts_clean==false while fast_forward_ok==true (the self-contradiction), so this fixture exits nonzero.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
