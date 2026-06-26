name: delegate-bridge.md v2 cold-reviewer recipe carries --setting-sources "" and is --bare-free
phase: 02 · execute-plan
owner: prompts.md § Prompt 2 (Phase 1)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DOC="$ROOT/docs/delegate-bridge.md"
  # Slice the v2 section, then isolate its cold-reviewer recipe block (anchored on the
  # real recipe first line `cd "$CTX" && claude -p`, not a prose mention), and assert the
  # Phase-0 contamination fix is intact: the v2 recipe MUST carry --setting-sources "" and
  # MUST NOT carry --bare (which breaks auth on current claude, R6). MUTATION: removing
  # --setting-sources "" or adding --bare to the v2 recipe block fails this guard.
  BLOCK=$(awk '/^# Integrated topology \(v2\)/,/^# v1 \/ watcher-attended fallback/' "$DOC" \
    | awk '/cd "\$CTX" && claude -p/{f=1} f{print} f&&/\/dev\/null/{exit}')
  printf '%s\n' "$BLOCK" | grep -Fq 'setting-sources ""' \
    && ! printf '%s\n' "$BLOCK" | grep -q -- '--bare' \
    && echo "v2-recipe-guard-ok"
expected: prints "v2-recipe-guard-ok" — the v2 cold-reviewer recipe in docs/delegate-bridge.md contains `--setting-sources ""` (the Phase-0 TEST 3 contamination fix) and no `--bare` (R6: --bare breaks auth on claude 2.1.187). The v1 section's `--bare` invocation is deliberately not matched (the slice stops at the v1 banner).
