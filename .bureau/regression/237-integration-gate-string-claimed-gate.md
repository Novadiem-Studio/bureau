name: integration-gate.sh — pre-existing-red validation tolerates string-form claimed gates (no 'str'.get crash)
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
  # --claimed-gates MIXES a bare STRING element ("regression") with a dict that is
  # result:"red", pre-existing:true. Pre-fix, the pre_existing_claimed comprehension
  # called .get() on the string → AttributeError, caught into errors[] at exit 0 (the
  # exact live cp09 signature). The crash is absorbed, so assert on errors[] CONTENT,
  # never the exit code.
  CLAIMED='[{"name":"npm-test","command":"false","result":"red","pre-existing":true},"regression"]'
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates "$CLAIMED" --state-json "$W/state.json" --out "$OUT" >/dev/null 2>&1 || true
  [ -f "$OUT/integration-results.json" ] || { echo "FAIL: no integration-results.json produced"; exit 1; }
  # The str.get crash surfaces as an errors[] string containing the AttributeError text.
  # Render errors[] to lines and grep (PATH-pinned, EC 10 ugrep guard) for the tell.
  errs=$(jq -r '.errors[]?' "$OUT/integration-results.json")
  if printf '%s\n' "$errs" | PATH=/usr/bin:$PATH grep -qF "object has no attribute 'get'"; then
    echo "FAIL: str.get crash surfaced in errors[]: $(jq -c '.errors' "$OUT/integration-results.json")"
    exit 1
  fi
  echo "PASS"
  # Mutation note: drop the `isinstance(g, dict) and` guard from the pre_existing_claimed
  # comprehension in the PRE_EXISTING_JSON heredoc (scripts/integration-gate.sh) → the
  # string element hits .get() → AttributeError → the "'str' object has no attribute
  # 'get'" note reappears in errors[] → this fixture goes RED.
expected: exit 0; stdout "PASS"; when --claimed-gates mixes a bare string with a red pre-existing dict, the pre-existing-red validation does NOT crash into errors[] with "'str' object has no attribute 'get'". The crash is absorbed at exit 0, so this asserts on errors[] content, not the exit code.
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 2 / scripts/integration-gate.sh PRE_EXISTING_JSON pre_existing_claimed isinstance guard
