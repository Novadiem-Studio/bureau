name: diff-target-missing-diff-sha-field-fails-schema (challenger-2 W-b)
phase: 04 · verdict-binding (FR 11)
owner: scripts/verdict-gate.sh — diff-target reviewed_artifacts element requires diff_sha
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
  printf '{"target_repo":"%s"}\n' "$REPO" > "$RUN_DIR/state.json"
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$RUN_DIR/verdicts/challenger-1.json" <<EOF
  {"attempt_id":"challenger-1","review_mode":"code-review","reviewed_artifacts":[{"kind":"diff-target","base_ref":"HEAD","base_sha":"$BASE_SHA","target_ref":"WORKING-TREE"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: verdict-gate exited $rc (expected 1): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "schema-violation" || { echo "FAIL: expected schema-violation, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: add "diff_sha":"$DIFF_SHA" to the diff-target element. The gate exits 0,
  # so the grep for "schema-violation" fails.
expected: PASS
