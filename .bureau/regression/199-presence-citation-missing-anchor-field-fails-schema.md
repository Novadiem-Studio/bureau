name: presence-citation-missing-anchor-field-fails-schema (challenger-2 W-b)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — presence citation requires anchor field
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  printf 'anchor exists here but field is omitted from JSON\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":["r1-b1"],"blockers":[{"id":"r1-b1","summary":"presence citation lacks anchor","citation":{"kind":"presence","path":"$ART"}}],"warnings":[],"verdict":"BLOCKED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "schema-violation" || { echo "FAIL: expected schema-violation, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: add an anchor field to the citation. The gate exits 0, so the grep for
  # "schema-violation" fails.
expected: PASS
