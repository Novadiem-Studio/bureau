name: F316 · verdict-gate.sh finds a presence-citation anchor that starts with "-" (grep -- ends options) (issue #115)
phase: 115 · integration gate regression runner resolution
owner: scripts/verdict-gate.sh — STEP 4 presence citation grep
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR/verdicts"
  ART="$TMPD/spec.md"
  printf 'deploy with\n--force only after review\n' > "$ART"
  SHA=$(shasum -a 256 "$ART" | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"spec-plan","reviewed_artifacts":[{"path":"$ART","sha256":"$SHA"}],"blocker_ids":["r1-b1"],"blockers":[{"id":"r1-b1","summary":"flag cited","citation":{"kind":"presence","path":"$ART","anchor":"--force only"}}],"warnings":[],"verdict":"BLOCKED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: verdict-gate exited $rc (expected 0): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "gate: clean" || { echo "FAIL: expected gate: clean, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: drop the `--` from `grep -qF -- "$_banchor" "$_bpath"`. grep then
  # reads "--force only" as an unknown option, exits 2, and the gate reports a false
  # citation-not-found with exit 1, failing the rc-eq-0 assertion.
expected: PASS
