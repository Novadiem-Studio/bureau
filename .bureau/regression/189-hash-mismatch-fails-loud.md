name: hash-mismatch-fails-loud (AC-3/EC-3)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — stale file hash exits with hash-mismatch
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  printf 'reviewed revision\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  printf 'mutated revision\n' > "$ART"
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "hash-mismatch" || { echo "FAIL: expected hash-mismatch, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: remove the hash-recompute step from verdict-gate.sh. The gate exits 0,
  # so the grep for "hash-mismatch" fails.
expected: PASS
