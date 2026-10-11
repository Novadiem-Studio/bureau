name: preflight-artifacts --phase final treats prompts as optional for bureau-lite only
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  mk() {
    mkdir -p "$1"
    printf '{"workflow":"%s","target_repo":"(no-target)"}\n' "$2" > "$1/state.json"
    printf '**FR 1 — Only FR**\nA requirement.\n' > "$1/spec.md"
    printf '## Phase 1: core\nThis implements FR 1.\n' > "$1/plan.md"
  }
  mk "$TMP/lite" bureau-lite
  out=$("$ROOT/scripts/preflight-artifacts.sh" "$TMP/lite" --phase final 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: bureau-lite without prompts flagged (exit $rc): $out"; exit 1; }
  mk "$TMP/feat" feature
  out=$("$ROOT/scripts/preflight-artifacts.sh" "$TMP/feat" --phase final 2>&1); rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'prompts.md' \
    || { echo "FAIL: feature without prompts not flagged: $out"; exit 1; }
  mk "$TMP/lite2" bureau-lite; mkdir -p "$TMP/lite2/prompts"
  out=$("$ROOT/scripts/preflight-artifacts.sh" "$TMP/lite2" --phase final 2>&1); rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF '00-index.md' \
    || { echo "FAIL: bureau-lite with an empty prompts/ folder not checked: $out"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. bureau-lite with no prompts artifact passes --phase final; feature without prompts is still flagged; bureau-lite with a prompts/ folder that exists but is empty is still checked (00-index.md absent). MUTATION — deleting the PROMPTS_OPTIONAL block in scripts/preflight-artifacts.sh flags the first case and the fixture exits non-zero.
phase: bureau-lite · issue #100
owner: scripts/preflight-artifacts.sh
