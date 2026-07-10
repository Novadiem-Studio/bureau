name: F07 · integration-gate.sh conflicts_clean legacy merge-tree fallback detects a genuine conflict (old-git path)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

  # BUREAU_FORCE_LEGACY_MERGETREE=1 skips the modern `git merge-tree --write-tree`
  # path and forces the classic 3-arg fallback, so this fixture exercises the
  # old-git code path even on a modern git (this host is 2.50.1). The fallback
  # must: (a) use the TRUE merge-base as arg 1 (base-as-own-merge-base makes a
  # real conflict resolve clean), and (b) match the `+`-prefixed conflict marker
  # the classic form emits (`+<<<<<<<`, not `<<<<<<<`).

  # ── CASE A: genuine same-line 3-way conflict, non-ff ⇒ conflicts_clean MUST be false.
  WA="$TMP/wtA"; OUTA="$TMP/ctxA"; mkdir -p "$WA/.bureau/regression" "$OUTA"
  git -C "$WA" init -q; git -C "$WA" config user.email t@t; git -C "$WA" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$WA/.bureau/regression/run.sh"
  printf 'line-original\n' > "$WA/conflict.txt"
  git -C "$WA" add -A; git -C "$WA" commit -qm base
  ANCESTOR=$(git -C "$WA" rev-parse HEAD)
  printf 'line-from-BASE-side\n' > "$WA/conflict.txt"; git -C "$WA" add -A; git -C "$WA" commit -qm base-advance
  BASEA=$(git -C "$WA" rev-parse HEAD)
  git -C "$WA" checkout -q -b feat "$ANCESTOR"
  printf 'line-from-HEAD-side\n' > "$WA/conflict.txt"; git -C "$WA" add -A; git -C "$WA" commit -qm head-advance
  printf '{"scope":{}}\n' > "$TMP/stateA.json"
  BUREAU_FORCE_LEGACY_MERGETREE=1 "$GATE" --checkpoint-type integration --worktree-path "$WA" --base-ref "$BASEA" \
    --claimed-gates '[]' --state-json "$TMP/stateA.json" --out "$OUTA"
  jq -e '.fast_forward_ok==false and .conflicts_clean==false and (has("verdict")|not)' "$OUTA/integration-results.json"

  # ── CASE B: clean non-ff merge (base and HEAD touch DIFFERENT files) ⇒
  # conflicts_clean MUST be true — the fallback must not flag a false conflict.
  WB="$TMP/wtB"; OUTB="$TMP/ctxB"; mkdir -p "$WB/.bureau/regression" "$OUTB"
  git -C "$WB" init -q; git -C "$WB" config user.email t@t; git -C "$WB" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$WB/.bureau/regression/run.sh"
  printf 'shared\n' > "$WB/shared.txt"
  git -C "$WB" add -A; git -C "$WB" commit -qm base
  ANCESTORB=$(git -C "$WB" rev-parse HEAD)
  printf 'base-only\n' > "$WB/fileA.txt"; git -C "$WB" add -A; git -C "$WB" commit -qm base-advance
  BASEB=$(git -C "$WB" rev-parse HEAD)
  git -C "$WB" checkout -q -b feat "$ANCESTORB"
  printf 'head-only\n' > "$WB/fileB.txt"; git -C "$WB" add -A; git -C "$WB" commit -qm head-advance
  printf '{"scope":{}}\n' > "$TMP/stateB.json"
  BUREAU_FORCE_LEGACY_MERGETREE=1 "$GATE" --checkpoint-type integration --worktree-path "$WB" --base-ref "$BASEB" \
    --claimed-gates '[]' --state-json "$TMP/stateB.json" --out "$OUTB"
  jq -e '.fast_forward_ok==false and .conflicts_clean==true and (has("verdict")|not)' "$OUTB/integration-results.json"
expected: exit 0 — with the legacy merge-tree fallback FORCED, CASE A (a real same-line 3-way conflict) yields conflicts_clean==false and CASE B (base/HEAD on different files) yields conflicts_clean==true; both non-ff, neither has a "verdict" key. MUTATION — reverting the fallback to the first-cut bug (arg1 = base itself instead of `git merge-base base HEAD`, AND the anchored `^<<<<<<< ` marker that never matches the classic `+<<<<<<<` output) makes CASE A resolve clean → conflicts_clean==true (a silent false all-clear) → this fixture exits nonzero.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/integration-gate.sh)
