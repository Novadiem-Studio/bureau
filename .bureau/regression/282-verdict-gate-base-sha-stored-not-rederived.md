name: verdict-gate-base-sha-stored-not-rederived (D4 — bare-ref build-diff uses stored SHA, not re-derived merge-base)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: scripts/verdict-gate.sh — D4 rev-parse DIFF_BASE_SHA (D4 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  # Use a real git repo (the bureau install itself) so rev-parse works
  REPO="$ROOT"
  # Get HEAD SHA and record it as base_sha (simulating a WORKING-TREE record
  # where HEAD at write time may differ from HEAD at gate time)
  BASE_SHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)
  # Compute the diff_sha from that base (empty diff against HEAD = empty diff)
  DIFF_SHA=$(git -C "$REPO" diff "$BASE_SHA" | shasum -a 256 | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"build-diff","reviewed_artifacts":[{"kind":"diff-target","base_ref":"main","base_sha":"$BASE_SHA","target_ref":"WORKING-TREE","diff_sha":"$DIFF_SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  # Record the target repo in state.json so verdict-gate can locate it
  cat > "$RUN_DIR/state.json" <<EOF
  {"target_repo":"$REPO"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  # Gate must pass clean (base_sha stored == rev-parse of stored SHA)
  [ "$rc" -eq 0 ] || { echo "FAIL: verdict-gate exited $rc (expected 0): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "gate: clean" || { echo "FAIL: expected gate: clean, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: revert the bare-ref *) case back to
  # `_recomputed_base=$(git -C "$R" merge-base HEAD "$DIFF_BASE_REF" 2>/dev/null)`.
  # When the working-tree also uses HEAD and base_ref is "main", merge-base HEAD main
  # may resolve differently from the stored base_sha if HEAD has advanced, causing
  # a diff-target-mutated DEFECT and exit 1, making the rc-eq-0 check fail.
expected: PASS
