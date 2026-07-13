name: missing-presence-citation-anchor-fails (AC-4/EC-4)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — presence citation anchor is spot-checked
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  printf 'this file deliberately lacks the blocker anchor\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":["r1-b1"],"blockers":[{"id":"r1-b1","summary":"anchor should be present","citation":{"kind":"presence","path":"$ART","anchor":"missing anchor text 12345"}}],"warnings":[],"verdict":"BLOCKED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "citation-not-found" || { echo "FAIL: expected citation-not-found, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: insert the anchor string into the cited file. The gate exits 0, so the
  # grep for "citation-not-found" fails.
expected: PASS
