name: diff-target-working-tree-mutated-fires (EC-12/EC-13/FR-3)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — diff-target working-tree binding detects mutation
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  REPO="$TMPD/repo"
  mkdir -p "$RUN_DIR/verdicts"
  git init -q "$REPO"
  git -C "$REPO" config user.email "fixture@example.test"
  git -C "$REPO" config user.name "Fixture"
  printf 'base\n' > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -q -m init
  printf 'base\nreviewed change\n' > "$REPO/file.txt"
  BASE_SHA=$(git -C "$REPO" rev-parse HEAD)
  DIFF_SHA=$(git -C "$REPO" diff "$BASE_SHA" | shasum -a 256 | awk '{print $1}')
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"target_repo":"%s"}\n' "$REPO" > "$RUN_DIR/state.json"
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"code-review","reviewed_artifacts":[{"kind":"diff-target","base_ref":"HEAD","base_sha":"$BASE_SHA","target_ref":"WORKING-TREE","diff_sha":"$DIFF_SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out_clean=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc_clean=$?
  [ "$rc_clean" -eq 0 ] || { echo "FAIL: initial gate exited $rc_clean (expected 0): $out_clean"; exit 1; }
  printf '%s\n' "$out_clean" | grep -q "gate: clean" || { echo "FAIL: expected initial gate: clean, got: $out_clean"; exit 1; }
  printf 'base\nreviewed change\nlater mutation\n' > "$REPO/file.txt"
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: mutated gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "diff-target-mutated" || { echo "FAIL: expected diff-target-mutated, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: remove the diff_sha recompute from verdict-gate.sh. The second gate call
  # exits 0, so the grep for "diff-target-mutated" fails.
expected: PASS
