name: watcher.sh spawn uses --bare, --system-prompt, --tools Read, --add-dir "$CTX" (not "$RUN_DIR")
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Deterministic static guard on the load-bearing identity/isolation flags in
  # the Delegate spawn invocation. MUTATION-HARDENED: every grep runs against the
  # script with COMMENT LINES STRIPPED, so a flag that survives only in a comment
  # (the header documents --bare/--system-prompt/--add-dir "$CTX") can no longer
  # satisfy the guard — the flag must be present in the real invocation. Patterns
  # containing a literal $ use grep -F because BSD/macOS grep BRE/ERE mishandles a
  # mid-pattern $.
  SCRIPT=$ROOT/scripts/watcher.sh
  # Strip full-line comments AND inline trailing comments, leaving only code.
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  strip "$SCRIPT" | grep -q -- '--bare' && \
  strip "$SCRIPT" | grep -q -- '--system-prompt' && \
  strip "$SCRIPT" | grep -Eq -- '--tools[[:space:]]+"Read"' && \
  strip "$SCRIPT" | grep -Fq 'add-dir "$CTX"' && \
  ! strip "$SCRIPT" | grep -Fq 'add-dir "$RUN_DIR"' && \
  echo "all-guards-present"
expected: prints "all-guards-present" — watcher.sh's real (non-comment) spawn invocation has --bare, --system-prompt, --tools "Read", --add-dir "$CTX"; and NO bare --add-dir "$RUN_DIR" (the read root is the staged context dir, EC1/EC8). Deleting any of these flags from the real `claude` invocation fails the guard even though the header comment still mentions them.
phase: 12 · principal-delegate
owner: scripts/watcher.sh
