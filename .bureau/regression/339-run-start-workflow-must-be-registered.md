name: run-start refuses a --workflow id with no workflows/<id>.md and accepts bureau-lite
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  TARGET="$TMPF/target"
  SLUG="20261011-wf-registered-$$"
  RUN_DIR="$TARGET/.bureau/runs/$SLUG"
  mkdir -p "$TARGET" "$TMPF/ptr"
  git -C "$TARGET" init -q
  cleanup() {
    rm -rf "$TMPF"
    rm -f "$ROOT/output/studio/runs-index/$SLUG.json" "$ROOT/output/studio/runs-index/.$SLUG.json.tmp"
  }
  trap cleanup EXIT INT TERM
  for bad in bureau_lite no-such-workflow index ../feature; do
    if BUREAU_POINTER_DIR="$TMPF/ptr" bash "$ROOT/scripts/run-start.sh" "$RUN_DIR" --target "$TARGET" \
         --workflow "$bad" --no-pointer-echo >/dev/null 2>"$TMPF/err"; then
      echo "FAIL: accepted --workflow $bad"; exit 1
    fi
    grep -q "unknown --workflow" "$TMPF/err" || { echo "FAIL: no clear error for $bad"; cat "$TMPF/err"; exit 1; }
    [ ! -e "$RUN_DIR" ] || { echo "FAIL: RUN_DIR created for $bad"; exit 1; }
  done
  BUREAU_POINTER_DIR="$TMPF/ptr" bash "$ROOT/scripts/run-start.sh" "$RUN_DIR" --target "$TARGET" \
    --workflow bureau-lite --no-pointer-echo >/dev/null 2>"$TMPF/ok.err" || { cat "$TMPF/ok.err"; exit 1; }
  jq -e '.workflow=="bureau-lite" and .workflow_shifts==[]' "$RUN_DIR/state.json" >/dev/null \
    || { echo "FAIL: state.json workflow/workflow_shifts wrong"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. bureau_lite, an unregistered id, "index" and a path-shaped id are refused with "unknown --workflow" before any RUN_DIR exists; bureau-lite starts and state.json carries workflow "bureau-lite" and workflow_shifts []. MUTATION — deleting the registered-workflow check in scripts/run-start.sh lets bureau_lite start, and the fixture exits non-zero.
phase: bureau-lite · issue #100
owner: scripts/run-start.sh + templates/state.json
