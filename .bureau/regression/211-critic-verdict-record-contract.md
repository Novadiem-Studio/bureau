name: critic-verdict-record-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  CRITIC="$ROOT/agents/critic.md"
  [ -f "$CRITIC" ] || { echo "FAIL: agents/critic.md missing"; exit 1; }

  grep -q '`review_mode` is exactly one of `spec-plan`, `prompts`, `build-diff`, `code-review`, or' "$CRITIC" \
    || { echo "FAIL: review_mode enum not stated"; exit 1; }
  grep -q '`verification`' "$CRITIC" \
    || { echo "FAIL: verification mode missing from enum text"; exit 1; }
  grep -q '`verdict` is derived, never free-typed' "$CRITIC" \
    || { echo "FAIL: derived verdict rule missing"; exit 1; }
  grep -q '`BLOCKED` when `blocker_ids` is' "$CRITIC" \
    || { echo "FAIL: BLOCKED enum rule missing"; exit 1; }
  grep -q '`APPROVED_WITH_WARNINGS`' "$CRITIC" \
    || { echo "FAIL: APPROVED_WITH_WARNINGS enum missing"; exit 1; }
  grep -q '`APPROVED` when both arrays are empty' "$CRITIC" \
    || { echo "FAIL: APPROVED enum rule missing"; exit 1; }
  grep -q '`reviewed_artifacts` is always an array' "$CRITIC" \
    || { echo "FAIL: reviewed_artifacts array rule missing"; exit 1; }
  grep -q '"kind":"diff-target","base_ref":"<ref>","base_sha":"<sha>","target_ref":"WORKING-TREE|<ref>","diff_sha":"<sha>"' "$CRITIC" \
    || { echo "FAIL: diff-target field shape missing"; exit 1; }
  grep -q 'do not write an object-shaped diff binding' "$CRITIC" \
    || { echo "FAIL: object-shaped diff binding prohibition missing"; exit 1; }

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
  {"attempt_id":"challenger-1","review_mode":"build-diff","reviewed_artifacts":[{"kind":"diff-target","base_ref":"HEAD","base_sha":"$BASE_SHA","target_ref":"WORKING-TREE","diff_sha":"$DIFF_SHA"}],"blocker_ids":[],"blockers":[],"warnings":[],"verdict":"APPROVED","timestamp":"$TS"}
  EOF
  out=$(bash "$ROOT/scripts/verdict-gate.sh" "$RUN_DIR" challenger-1 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: persona-stated diff-target shape rejected by verdict-gate: $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "gate: clean" || { echo "FAIL: expected gate: clean, got: $out"; exit 1; }
  echo "PASS"
  # Mutation note: removing the persona enum/shape text makes the greps fail;
  # changing the sample record's diff-target field set makes verdict-gate fail.
expected: exit 0; stdout "PASS"; critic persona states the verdict/review_mode enums, reviewed_artifacts array rule, diff-target field shape, object-shaped binding ban, and the stated build-diff shape is accepted by verdict-gate.
phase: 01 · feature (Bundle 33)
owner: agents/critic.md § Verdict record + scripts/verdict-gate.sh schema

