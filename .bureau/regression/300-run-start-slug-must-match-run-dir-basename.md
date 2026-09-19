name: run-start.sh refuses a --slug that disagrees with RUN_DIR's basename, and derives it automatically when --slug is omitted
phase: bug-fix · runs-index slug/RUN_DIR mismatch
owner: scripts/run-start.sh --slug validation; scripts/update-runs-index.sh (silent-no-op-to-warning)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  DATED_SLUG="20260918-slugfixture300-$$"
  TARGET="$TMPF/target"
  RUN_DIR="$TARGET/.bureau/runs/$DATED_SLUG"
  POINTER_DIR="$TMPF/pointers"
  mkdir -p "$TARGET" "$POINTER_DIR"
  git -C "$TARGET" init -q
  cleanup() {
    rm -rf "$TMPF" "$RUN_DIR"
    rm -f "$ROOT/output/studio/runs-index/$DATED_SLUG.json" "$ROOT/output/studio/runs-index/.$DATED_SLUG.json.tmp"
    rm -f "$ROOT/output/studio/runs-index/slugfixture300-$$.json" "$ROOT/output/studio/runs-index/.slugfixture300-$$.json.tmp"
  }
  trap cleanup EXIT INT TERM

  # ── (a) MISMATCH: an undated task-slug passed via --slug, while RUN_DIR carries the
  # dated form — the exact shape of the bug (real runs like "1a0-module-contract" got an
  # index entry under the undated slug while RUN_DIR was "20260918-1a0-module-contract",
  # so update-runs-index.sh's basename(RUN_DIR) lookup could never find it again). This
  # must be refused, loudly, with NO RUN_DIR and NO orphaned index entry left behind.
  UNDATED_SLUG="slugfixture300-$$"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" \
    "$RUN_DIR" --target "$TARGET" --workflow feature --slug "$UNDATED_SLUG" \
    --no-pointer-echo >"$TMPF/mismatch.out" 2>"$TMPF/mismatch.err"
  rc=$?
  [ "$rc" -ne 0 ] || { echo "FAIL: run-start accepted a --slug that disagrees with RUN_DIR's basename"; exit 1; }
  grep -q "does not match RUN_DIR's basename" "$TMPF/mismatch.err" \
    || { echo "FAIL: mismatch was not reported on stderr"; cat "$TMPF/mismatch.err"; exit 1; }
  [ ! -e "$RUN_DIR" ] || { echo "FAIL: RUN_DIR was created despite the slug mismatch"; exit 1; }
  [ ! -f "$ROOT/output/studio/runs-index/$UNDATED_SLUG.json" ] \
    || { echo "FAIL: an orphaned index entry was written under the undated slug"; exit 1; }

  # ── (b) OMITTED --slug: derives from RUN_DIR's basename automatically and succeeds.
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" \
    "$RUN_DIR" --target "$TARGET" --workflow feature \
    --no-pointer-echo >/dev/null 2>"$TMPF/omitted.err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: run-start with --slug omitted exited $rc"; cat "$TMPF/omitted.err"; exit 1; }
  [ -f "$ROOT/output/studio/runs-index/$DATED_SLUG.json" ] \
    || { echo "FAIL: no index entry written under RUN_DIR's basename when --slug was omitted"; exit 1; }
  [ "$(jq -r .slug "$ROOT/output/studio/runs-index/$DATED_SLUG.json")" = "$DATED_SLUG" ] \
    || { echo "FAIL: index entry's slug field does not equal RUN_DIR's basename"; exit 1; }

  # ── (c) update-runs-index.sh now finds and mirrors this entry (the bug's actual symptom:
  # it used to silently no-op forever because the entry lived under a different filename).
  printf '%s\n' '{"workflow":"feature","phases_complete":["analyst"],"phase_status":"in_progress","phase":"architect","last_updated":"2026-09-18T12:00:00Z"}' > "$RUN_DIR/state.json"
  bash "$ROOT/scripts/update-runs-index.sh" "$RUN_DIR" 2>"$TMPF/mirror.err" \
    || { echo "FAIL: update-runs-index exited non-zero"; exit 1; }
  [ ! -s "$TMPF/mirror.err" ] || { echo "FAIL: update-runs-index warned on a real, findable entry"; cat "$TMPF/mirror.err"; exit 1; }
  jq -e '.status == "in_progress" and .phase == "architect"' "$ROOT/output/studio/runs-index/$DATED_SLUG.json" > /dev/null \
    || { echo "FAIL: update-runs-index did not mirror state.json into the (now-findable) entry"; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS"; a --slug disagreeing with RUN_DIR's basename is refused before RUN_DIR or any index entry is created (stderr names the mismatch); omitting --slug derives it from RUN_DIR's basename automatically; update-runs-index.sh then finds and mirrors that entry with no stderr warning.
