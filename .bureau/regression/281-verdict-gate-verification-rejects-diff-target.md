name: verdict-gate-verification-rejects-diff-target (D3 — verification mode rejects diff-target artifacts in STEP2)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: scripts/verdict-gate.sh — D3 mode-binding validation (D3 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Write a verification record with a diff-target artifact (invalid binding)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"verification","reviewed_artifacts":[{"kind":"diff-target","base_ref":"main","base_sha":"aabbccdd","target_ref":"WORKING-TREE","diff_sha":"ddeeff00"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  # Must exit 1 (DEFECT) not 0
  [ "$rc" -ne 0 ] || { echo "FAIL: verdict-gate exited 0 (expected non-zero) — diff-target accepted for verification"; exit 1; }
  # Must name the mode-binding violation
  printf '%s\n' "$out" | grep -qF 'diff-target' \
    || { echo "FAIL: output does not mention diff-target: $out"; exit 1; }
  printf '%s\n' "$out" | grep -qF 'verification' \
    || { echo "FAIL: output does not mention verification: $out"; exit 1; }
  echo "PASS"
  # Mutation note: delete the _file_modes/_diff_modes/_record_mode block and the
  # two mode-binding print+sys.exit(1) checks from STEP2. The gate then exits 0
  # with "gate: clean" — the rc check triggers and the fixture fails.
expected: PASS
