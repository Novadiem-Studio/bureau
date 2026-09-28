name: integration-gate.sh — cut-symbol attribution is per-symbol/per-file by line kind; only added-line hits fail scope_diff_clean (issue #43)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W/.bureau/regression" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  cat > "$W/src.c" <<'C'
  int header_only_marker = 0;

  void do_work(void) {
    int context_only = 1;
    int removed_only = 1;
    int stable = 0;
  }
  C
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  cat > "$W/src.c" <<'C'
  int header_only_marker = 0;

  void do_work(void) {
    int context_only = 1;
    int stable = 2;
  }
  C
  git -C "$W" add -A; git -C "$W" commit -qm "context+removed+header only"
  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":["worker_loop","header_only_marker","context_only","removed_only","deleted_only"]}}\n' > "$TMP/state.json"

  # Case A: only removed/context/header mentions are present => scope_diff_clean stays true.
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==true and
    (.scope.cut_symbol_hits | sort) == ["context_only","header_only_marker","removed_only"] and
    .scope.cut_symbol_attribution.header_only_marker.files["src.c"].header >= 1 and
    .scope.cut_symbol_attribution.context_only.files["src.c"].context >= 1 and
    .scope.cut_symbol_attribution.removed_only.files["src.c"].removed >= 1 and
    .scope.cut_symbol_attribution.worker_loop.total.added == 0
  ' "$OUT/integration-results.json"

  # Case B: added-line hit appears => scope_diff_clean flips false, with per-file attribution.
  cat > "$W/src.c" <<'C'
  int header_only_marker = 0;

  void do_work(void) {
    int context_only = 1;
    int stable = 2;
    int worker_loop = 1;
  }
  C
  git -C "$W" add -A; git -C "$W" commit -qm "introduce cut symbol on added line"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==false and
    (.scope.cut_symbol_hits | sort) == ["context_only","header_only_marker","removed_only","worker_loop"] and
    .scope.cut_symbol_attribution.worker_loop.files["src.c"].added >= 1 and
    .scope.cut_symbol_attribution.worker_loop.total.removed == 0 and
    .scope.cut_symbol_attribution.worker_loop.total.context == 0 and
    .scope.cut_symbol_attribution.worker_loop.total.header == 0
  ' "$OUT/integration-results.json"

  # Case C: added content line `++ ...` does not get misread as a file header.
  cat > "$W/src.c" <<'C'
  int header_only_marker = 0;

  void do_work(void) {
    int context_only = 1;
    int stable = 2;
    ++ counter;
    worker_loop();
  }
  C
  git -C "$W" add -A; git -C "$W" commit -qm "line starts with ++ and still scans later additions"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==false and
    .scope.cut_symbol_attribution.worker_loop.files["src.c"].added >= 1
  ' "$OUT/integration-results.json"

  # Case D: added `++worker_loop` is classified as an added line (not skipped).
  cat > "$W/src.c" <<'C'
  int header_only_marker = 0;

  void do_work(void) {
    int context_only = 1;
    int stable = 2;
    ++worker_loop;
  }
  C
  git -C "$W" add -A; git -C "$W" commit -qm "added line begins with ++worker_loop"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==false and
    .scope.cut_symbol_attribution.worker_loop.files["src.c"].added >= 1
  ' "$OUT/integration-results.json"

  # Case E: removed `-- worker_loop` counts as removed (informational, non-blocking).
  cat > "$W/q.sql" <<'SQL'
  -- worker_loop here
  select 1;
  SQL
  git -C "$W" add -A; git -C "$W" commit -qm "add sql with removed marker token"
  BASE_SQL=$(git -C "$W" rev-parse HEAD)
  cat > "$W/q.sql" <<'SQL'
  select 1;
  SQL
  git -C "$W" add -A; git -C "$W" commit -qm "remove sql marker token line"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_SQL" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==true and
    .scope.cut_symbol_attribution.worker_loop.files["q.sql"].removed >= 1
  ' "$OUT/integration-results.json"

  # Case F: deleted-file hunks attribute removed lines via the old (--- a/...) path.
  cat > "$W/deleted.c" <<'C'
  int deleted_only = 1;
  C
  git -C "$W" add -A; git -C "$W" commit -qm "add file to delete"
  BASE_DELETED=$(git -C "$W" rev-parse HEAD)
  git -C "$W" rm -q deleted.c
  git -C "$W" commit -qm "delete file with cut symbol"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_DELETED" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==true and
    .scope.cut_symbol_attribution.deleted_only.files["deleted.c"].removed >= 1
  ' "$OUT/integration-results.json"

  # Case G: quoted non-ASCII diff paths decode to UTF-8 file keys.
  cat > "$W/café.c" <<'C'
  int stable = 0;
  C
  git -C "$W" add -A; git -C "$W" commit -qm "add non-ascii file"
  BASE_NONASCII=$(git -C "$W" rev-parse HEAD)
  cat > "$W/café.c" <<'C'
  int stable = 0;
  int worker_loop = 1;
  C
  git -C "$W" add -A; git -C "$W" commit -qm "add symbol in non-ascii file"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_NONASCII" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==false and
    .scope.cut_symbol_attribution.worker_loop.files["café.c"].added >= 1
  ' "$OUT/integration-results.json"
  # Case H: added-line content that only a non-newline splitter would break
  # (form feed, vertical tab, U+2028, lone CR) is still one added line and blocks.
  for BYTES in '\x0c' '\x0b' '\xe2\x80\xa8' '\r'; do
    printf 'int a;\n' > "$W/split.c"
    git -C "$W" add -A; git -C "$W" commit -qm "split base"
    BASE_SPLIT=$(git -C "$W" rev-parse HEAD)
    printf "int a;\nq;${BYTES}worker_loop();\n" > "$W/split.c"
    git -C "$W" add -A; git -C "$W" commit -qm "split head"
    "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_SPLIT" \
      --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
    jq -e '
      .scope.scope_diff_clean==false and
      .scope.cut_symbol_attribution.worker_loop.files["split.c"].added >= 1
    ' "$OUT/integration-results.json"
  done

  # Case I: repo colour config does not blind the scan.
  git -C "$W" config color.ui always; git -C "$W" config color.diff always
  BASE_COLOR=$(git -C "$W" rev-parse HEAD)
  printf 'int worker_loop_colour = 1;\n' >> "$W/split.c"
  git -C "$W" add -A; git -C "$W" commit -qm "colour head"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_COLOR" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '.scope.scope_diff_clean==false' "$OUT/integration-results.json"
  git -C "$W" config --unset color.ui; git -C "$W" config --unset color.diff

  # Case J: a new file whose path names a cut symbol blocks, attributed as kind "path".
  BASE_PATH=$(git -C "$W" rev-parse HEAD)
  : > "$W/worker_loop.c"
  git -C "$W" add -A; git -C "$W" commit -qm "empty file named for the cut symbol"
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE_PATH" \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT"
  jq -e '
    .scope.scope_diff_clean==false and
    .scope.cut_symbol_attribution.worker_loop.files["worker_loop.c"].path == 1 and
    (.scope | has("parse_error") | not)
  ' "$OUT/integration-results.json"
  echo "PASS"
expected: exit 0; stdout "PASS"; scope includes per-symbol/per-file line-kind attribution (`added`/`removed`/`context`/`header`), `cut_symbol_hits` remains a list of symbol strings, `scope_diff_clean` is true when hits are only removed/context/header and false only when an added-line hit is introduced, `++worker_loop` content lines are classified as added (blocking), removed `-- worker_loop` lines are classified as removed (informational, non-blocking), deleted-file removed-line hits attribute to the old path, quoted non-ASCII paths decode to UTF-8 file keys, form feed / vertical tab / U+2028 / lone CR inside an added line do not split it out of the scan, repo colour config does not blind it, and a new file whose path names a cut symbol blocks with kind `path`.
phase: bug-fix · issue-43
owner: issue #43 / scripts/integration-gate.sh — attributed cut-symbol scanning with added-line-only fail semantics
