name: verdict-gate-base-sha-stored-not-rederived (D4 — bare-ref build-diff uses stored SHA, not re-derived merge-base)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: scripts/verdict-gate.sh — D4 rev-parse DIFF_BASE_SHA in the bare-ref *) case (D4 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  # Build a throwaway repo where, AT GATE TIME, `merge-base HEAD <base_ref>`
  # resolves to a DIFFERENT commit than the base_sha stored in the record.
  # This exercises the bare-ref *) path (target_ref is a committed ref, base_ref
  # a bare branch name) and triggers the exact drift D4 defends against.
  REPO="$TMPD/repo"
  git init -q -b base "$REPO"
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
  # C0 on base
  printf 'A\n' > "$REPO/f.txt"
  git -C "$REPO" add f.txt
  git -C "$REPO" commit -qm C0
  C0=$(git -C "$REPO" rev-parse HEAD)
  # feature branches off C0 and adds a commit (the committed diff target)
  git -C "$REPO" checkout -q -b feature
  printf 'A\nB\n' > "$REPO/f.txt"
  git -C "$REPO" add f.txt
  git -C "$REPO" commit -qm C1
  FEAT=$(git -C "$REPO" rev-parse HEAD)
  # Record base_sha = merge-base(feature, base) = C0, and diff_sha = diff(C0, feature).
  BASE_SHA=$(git -C "$REPO" merge-base feature base)
  DIFF_SHA=$(git -C "$REPO" diff "$BASE_SHA" "$FEAT" | shasum -a 256 | awk '{print $1}')
  # DRIFT: advance the base branch up to feature's tip. feature (the target) never
  # moves and HEAD stays on feature; only `merge-base HEAD base` shifts (C0 -> FEAT).
  git -C "$REPO" branch -f base "$FEAT"
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"build-diff","reviewed_artifacts":[{"kind":"diff-target","base_ref":"base","base_sha":"$BASE_SHA","target_ref":"$FEAT","diff_sha":"$DIFF_SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  cat > "$RUN_DIR/state.json" <<EOF
  {"target_repo":"$REPO"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  # FIXED code: rev-parse of the STORED base_sha (C0) still resolves -> base check
  # passes, diff(C0,feature) matches -> gate clean. OLD code: merge-base HEAD base
  # now yields FEAT != stored C0 -> diff-target-mutated DEFECT -> exit 1.
  [ "$rc" -eq 0 ] || { echo "FAIL: verdict-gate exited $rc (expected 0): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "gate: clean" || { echo "FAIL: expected gate: clean, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: revert the bare-ref *) case back to
  # `_recomputed_base=$(git -C "$R" merge-base HEAD "$DIFF_BASE_REF" 2>/dev/null)`.
  # Because the base branch was advanced to feature's tip after the record was
  # written, `merge-base HEAD base` re-derives FEAT, which != the stored base_sha
  # (C0). The base_sha-changed check then fires a diff-target-mutated DEFECT and
  # the gate exits 1, failing the rc-eq-0 assertion above (fixture goes RED).
expected: PASS
