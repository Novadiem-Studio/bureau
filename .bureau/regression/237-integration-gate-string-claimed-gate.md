name: integration-gate.sh — string-form claimed gates are coerced out at BOTH unguarded consumers (no 'str'.get crash; under-declaration not silently emptied)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; OUT="$TMP/ctx"; mkdir -p "$W" "$OUT"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # A real 2-commit worktree so the pre-existing-red loop actually runs (it adds a
  # detached base-ref worktree and re-runs each claimed pre-existing gate).
  echo v1 > "$W/f"; git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  echo v2 > "$W/f"; git -C "$W" commit -qam tip
  printf '{}' > "$W/state.json"

  # ── ASSERTION 1 (Bug 2) — pre-existing-red validation tolerates a string claimed gate ──
  # --claimed-gates MIXES a bare STRING element ("regression") with a dict that is
  # result:"red", pre-existing:true. Pre-fix, the pre_existing_claimed comprehension
  # called .get() on the string → AttributeError, caught into errors[] at exit 0 (the
  # exact live cp09 signature). The crash is absorbed, so assert on errors[] CONTENT,
  # never the exit code.
  CLAIMED='[{"name":"npm-test","command":"false","result":"red","pre-existing":true},"regression"]'
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates "$CLAIMED" --state-json "$W/state.json" --out "$OUT" >/dev/null 2>&1 || true
  [ -f "$OUT/integration-results.json" ] || { echo "FAIL: no integration-results.json produced (Bug 2)"; exit 1; }
  # The str.get crash surfaces as an errors[] string containing the AttributeError text.
  # Render errors[] to lines and grep (PATH-pinned, EC 10 ugrep guard) for the tell.
  errs=$(jq -r '.errors[]?' "$OUT/integration-results.json")
  if printf '%s\n' "$errs" | PATH=/usr/bin:$PATH grep -qF "object has no attribute 'get'"; then
    echo "FAIL: str.get crash surfaced in errors[] (Bug 2): $(jq -c '.errors' "$OUT/integration-results.json")"
    exit 1
  fi

  # ── ASSERTION 2 (W1 follow-up) — under-declaration check is not silently emptied by a string claimed gate ──
  # Same class as Bug 2, sibling consumer: the UNDER-DECLARATION heredoc iterates the same
  # `claimed` array and builds claimed_names/claimed_cmds with g.get() (:376-377). Pre-fix
  # (unguarded there), a bare STRING element throws AttributeError, which the heredoc's own
  # `try/except` swallows → under=[] → a REAL under-declaration is MISSED (masked), with NO
  # trace in errors[] (this heredoc's except does not record). We construct a claimed set that
  # mixes a bare STRING with a DICT gate that does NOT cover the canonical "regression" gate the
  # script always runs — so the "regression" gate SHOULD be reported as under-declared. Post-fix,
  # the string is coerced out (isinstance guard), the dict still doesn't cover "regression", and
  # the real under-declaration is correctly reported. Assert the "regression" gate appears in
  # under_declaration[] (non-empty AND correctly named) — the exact behaviour the string masked.
  OUT2="$TMP/ctx2"; mkdir -p "$OUT2"
  CLAIMED_UD='["regression",{"name":"npm-build","command":"npm run build","result":"green"}]'
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates "$CLAIMED_UD" --state-json "$W/state.json" --out "$OUT2" >/dev/null 2>&1 || true
  [ -f "$OUT2/integration-results.json" ] || { echo "FAIL: no integration-results.json produced (W1)"; exit 1; }
  ud_names=$(jq -r '.under_declaration[].name' "$OUT2/integration-results.json")
  if ! printf '%s\n' "$ud_names" | PATH=/usr/bin:$PATH grep -qx "regression"; then
    echo "FAIL: under-declaration silently emptied by string claimed gate (W1) — expected 'regression' in under_declaration[], got: $(jq -c '.under_declaration' "$OUT2/integration-results.json")"
    exit 1
  fi

  echo "PASS"
  # Mutation notes (two independent guards, one per assertion):
  #  ASSERTION 1 (Bug 2): drop `isinstance(g, dict) and` from the pre_existing_claimed
  #    comprehension in the PRE_EXISTING_JSON heredoc (:312) → the string hits .get() →
  #    AttributeError → the "'str' object has no attribute 'get'" note reappears in errors[] → RED.
  #  ASSERTION 2 (W1): drop the `if isinstance(g, dict)` guard from BOTH claimed_names/claimed_cmds
  #    set-comprehensions in the UNDER_DECL_JSON heredoc (:376-377) → the string throws → the
  #    heredoc's try/except sets under=[] → the real "regression" under-declaration is MISSED →
  #    under_declaration[] no longer contains "regression" → RED. (Verified against current HEAD,
  #    which already carries the :312 Bug-2 fix but not the :376-377 guard: under_declaration=[].)
expected: exit 0; stdout "PASS"; when --claimed-gates mixes a bare string with dict gates, BOTH unguarded consumers coerce the string out: (1) the pre-existing-red validation does NOT crash into errors[] with "'str' object has no attribute 'get'" (crash absorbed at exit 0 — assert on errors[] content), and (2) the under-declaration check is NOT silently emptied — a real under-declared canonical gate ("regression") is still reported in under_declaration[].
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 2 + W1 follow-up / scripts/integration-gate.sh — isinstance(g, dict) guard on BOTH claimed-array consumers (PRE_EXISTING_JSON :312 + UNDER_DECL_JSON :376-377)
