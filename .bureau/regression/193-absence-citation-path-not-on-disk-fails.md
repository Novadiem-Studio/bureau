name: absence-citation-path-not-on-disk-fails (AC-19/FR-11)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — absence citation path must exist
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  MISSING="$TMPD/missing-plan.md"
  printf 'absence citation fixture artifact\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":["r1-b1"],"blockers":[{"id":"r1-b1","summary":"missing coverage","citation":{"kind":"absence","path":"$MISSING","missing":"required coverage is absent"}}],"warnings":[],"verdict":"BLOCKED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "citation-path-not-found" || { echo "FAIL: expected citation-path-not-found, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: create a file at the cited absence path. The gate exits 0, so the grep
  # for "citation-path-not-found" fails.
expected: PASS
