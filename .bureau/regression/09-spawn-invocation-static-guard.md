name: watcher.sh spawn: NO --bare, has --setting-sources "", --system-prompt, --tools "Read", --add-dir "$CTX" (not "$RUN_DIR")
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Deterministic static guard on the load-bearing identity/isolation flags in the
  # Delegate spawn invocation. MUTATION-HARDENED: every grep runs against the script
  # with COMMENT LINES STRIPPED, so a flag that survives only in a comment (the
  # header still documents --setting-sources ""/--system-prompt/--add-dir "$CTX",
  # and mentions --bare to explain why it was dropped) can no longer satisfy — or
  # defeat — the guard. Bundle 15 P4 dropped --bare (R6: it breaks auth on claude
  # 2.1.187) and made --setting-sources "" the load-bearing CLAUDE.md-suppression
  # guard; so this fixture now asserts --bare is ABSENT from the real invocation and
  # --setting-sources "" is PRESENT. Patterns containing a literal $ use grep -F
  # because BSD/macOS grep BRE/ERE mishandles a mid-pattern $.
  SCRIPT=$ROOT/scripts/watcher.sh
  # Strip full-line comments AND inline trailing comments, leaving only code.
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  ! strip "$SCRIPT" | grep -q -- '--bare' && \
  strip "$SCRIPT" | grep -Fq -- '--setting-sources ""' && \
  strip "$SCRIPT" | grep -q -- '--system-prompt' && \
  strip "$SCRIPT" | grep -Eq -- '--tools[[:space:]]+"Read"' && \
  strip "$SCRIPT" | grep -Fq 'add-dir "$CTX"' && \
  ! strip "$SCRIPT" | grep -Fq 'add-dir "$RUN_DIR"' && \
  echo "all-guards-present"
expected: prints "all-guards-present" — watcher.sh's real (non-comment) spawn invocation has NO --bare (Bundle 15 P4 dropped it; R6: --bare breaks auth on claude 2.1.187), and HAS --setting-sources "" (now the CLAUDE.md-discovery + settings.json suppression guard), --system-prompt, --tools "Read", --add-dir "$CTX", and NO bare --add-dir "$RUN_DIR" (the read root is the staged context dir, EC1/EC8). Re-introducing --bare to the real invocation, or deleting --setting-sources "" / --system-prompt / --tools "Read" / --add-dir "$CTX" from it, fails the guard even though the header comments still mention those flags.
phase: 12 · principal-delegate (guard updated 2b · execute-plan, Bundle 15 P4)
owner: scripts/watcher.sh
