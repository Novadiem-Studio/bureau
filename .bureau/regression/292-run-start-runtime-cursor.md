name: run-start --runtime cursor resolves and persists a Cursor Agent run without changing the Claude default
phase: multi-host Cursor adapter
owner: scripts/run-start.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  SLUG="20260914-cursor-runtime-fixture-$$"
  TARGET="$TMPF/target"
  RUN_DIR="$TARGET/.bureau/runs/$SLUG"
  POINTER_DIR="$TMPF/pointers"
  mkdir -p "$TARGET" "$POINTER_DIR"
  git -C "$TARGET" init -q
  cleanup() {
    rm -rf "$TMPF"
    rm -f "$ROOT/output/studio/runs-index/$SLUG.json" "$ROOT/output/studio/runs-index/.$SLUG.json.tmp"
  }
  trap cleanup EXIT INT TERM

  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" \
    "$RUN_DIR" --target "$TARGET" --workflow feature --slug "$SLUG" \
    --runtime cursor --no-pointer-echo >/dev/null 2>"$TMPF/stderr"
  rc=$?
  [ "$rc" -eq 0 ] || { cat "$TMPF/stderr"; echo "FAIL: run-start exited $rc"; exit 1; }
  [ "$(jq -r .runtime "$RUN_DIR/model-routing.json")" = "cursor" ] \
    || { echo "FAIL: runtime was not cursor"; exit 1; }
  [ "$(jq -r .roles.delegate.model "$RUN_DIR/model-routing.json")" = "gpt-5.6-sol-medium" ] \
    || { echo "FAIL: Delegate model was not resolved through the Cursor adapter"; exit 1; }
  [ "$(jq -r .roles.analyst.model "$RUN_DIR/model-routing.json")" = "composer-2.5-fast" ] \
    || { echo "FAIL: Analyst model was not Composer fast"; exit 1; }
  [ "$(jq -r .roles.challenger.model "$RUN_DIR/model-routing.json")" = "gpt-5.6-sol-medium" ] \
    || { echo "FAIL: Challenger model was not Sol medium"; exit 1; }
  grep -q 'Host runtime resolved — runtime: cursor' "$RUN_DIR/log.md" \
    || { echo "FAIL: resolved runtime was not logged"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; `--runtime cursor` creates a Cursor model-routing.json and logs the host runtime.
