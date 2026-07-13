name: schema-violation-missing-required-field-fails (AC-5/EC-5)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — missing required record field is schema-violation
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  printf 'schema fixture artifact\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":[],"blockers":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "schema-violation" || { echo "FAIL: expected schema-violation, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: add the missing warnings field. The gate exits 0, so the grep for
  # "schema-violation" fails.
expected: PASS
