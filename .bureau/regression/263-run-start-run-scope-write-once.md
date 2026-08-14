name: run-start writes the four-field run-scope nonce once for a run's life
owner: scripts/run-start.sh run-scope nonce enrolment
phase: 05 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  TARGET="$TMPF/target"
  POINTER_DIR="$TMPF/active-runs"
  SLUG="20260813-run-scope-write-once-$$"
  RUN_DIR="$TARGET/.bureau/runs/$SLUG"
  mkdir -p "$TARGET" "$POINTER_DIR"
  git -C "$TARGET" init -q
  cleanup() {
    rm -rf "$TMPF"
    rm -f "$ROOT/output/studio/runs-index/$SLUG.json" "$ROOT/output/studio/runs-index/.$SLUG.json.tmp"
  }
  trap cleanup EXIT INT TERM
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" "$RUN_DIR" \
    --target "$TARGET" --workflow feature --slug "$SLUG" --no-pointer-echo >/dev/null 2>"$TMPF/first.err" \
    || { cat "$TMPF/first.err"; exit 1; }
  KEY=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')
  POINTER_FILE="$POINTER_DIR/$KEY"
  jq -e --arg run "$RUN_DIR" '
    .run_dir == $run and (.nonce | type == "string" and length > 0)
    and (.written_at | type == "string" and length > 0)
    and (.project_dir | type == "string" and length > 0)
    and (keys | sort) == ["nonce","project_dir","run_dir","written_at"]
    and (has("baseline") | not)
  ' "$POINTER_FILE" >/dev/null || { echo "FAIL: wrong run-scope shape"; exit 1; }
  first_nonce=$(jq -r '.nonce' "$POINTER_FILE")
  first_written_at=$(jq -r '.written_at' "$POINTER_FILE")
  rm -rf "$RUN_DIR"
  rm -f "$ROOT/output/studio/runs-index/$SLUG.json" "$ROOT/output/studio/runs-index/.$SLUG.json.tmp"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" "$RUN_DIR" \
    --target "$TARGET" --workflow feature --slug "$SLUG" --no-pointer-echo >/dev/null 2>"$TMPF/second.err" \
    || { cat "$TMPF/second.err"; exit 1; }
  [ "$(jq -r '.nonce' "$POINTER_FILE")" = "$first_nonce" ] \
    || { echo "FAIL: nonce rotated"; exit 1; }
  [ "$(jq -r '.written_at' "$POINTER_FILE")" = "$first_written_at" ] \
    || { echo "FAIL: written_at changed"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; exact four-field shape with no baseline, and the second same-RUN_DIR ceremony preserves nonce + written_at
