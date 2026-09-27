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
  printf '{"scope":{"allowed_paths":["**"],"cut_symbols":["worker_loop","header_only_marker","context_only","removed_only"]}}\n' > "$TMP/state.json"

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
  echo "PASS"
expected: exit 0; stdout "PASS"; scope includes per-symbol/per-file line-kind attribution (`added`/`removed`/`context`/`header`), `cut_symbol_hits` remains a list of symbol strings, and `scope_diff_clean` is true when hits are only removed/context/header and false only when an added-line hit is introduced.
phase: bug-fix · issue-43
owner: issue #43 / scripts/integration-gate.sh — attributed cut-symbol scanning with added-line-only fail semantics
