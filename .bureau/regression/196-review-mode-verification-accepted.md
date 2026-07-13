name: review-mode-verification-accepted (AC-18)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — verification is accepted as a file-target mode
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/verification.md"
  printf 'verification reviewed artifact\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"verification","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: verdict-gate exited $rc (expected 0): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "gate: clean" || { echo "FAIL: expected gate: clean, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: change review_mode to unknown-mode. The gate exits 1 with
  # schema-violation, so the "gate: clean" grep fails.
expected: PASS
