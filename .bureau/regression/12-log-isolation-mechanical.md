name: watcher.sh never copies log.md into the staged context dir (log isolation)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Static source guard for EC8: the staged NN-context dir is the Delegate's only
  # read root, and log.md must never be copied into it. MUTATION-HARDENED: every
  # grep runs against the script with COMMENT LINES STRIPPED, so a `cp ... log.md
  # ... CTX` line cannot be hidden behind (nor a flag satisfied by) the header
  # comments that discuss it; the negative cp clause and the read-root clause both
  # test real code. The read-root clause is the genuine BEHAVIORAL backstop: if a
  # variable-indirected copy (LOGSRC=...; cp "$LOGSRC" "$CTX") ever sneaks a log
  # in, the Delegate's read root being "$CTX" (not "$RUN_DIR") still bounds what it
  # can see. None of these patterns contains a literal $ in the cp clause, so ERE
  # (grep -E) is safe; the --add-dir assertions use grep -F (literal $).
  SCRIPT=$ROOT/scripts/watcher.sh
  # Strip full-line comments AND inline trailing comments, leaving only code.
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  # No `cp ... log.md ...` line that targets the context/CTX dir (count over code only).
  CPLOG=$(strip "$SCRIPT" | grep -Ec 'cp[[:space:]].*log\.md.*(CTX|context)' | tr -d ' ')
  echo "cp-log-into-context:$CPLOG"
  # The read root is the staged context dir, not the run dir (behavioral backstop).
  strip "$SCRIPT" | grep -Fq 'add-dir "$CTX"' && ! strip "$SCRIPT" | grep -Fq 'add-dir "$RUN_DIR"' \
    && echo "read-root:context"
expected: prints "cp-log-into-context:0" and "read-root:context" — no real (non-comment) watcher.sh line copies log.md into the context dir, and the Delegate's read root is "$CTX" not "$RUN_DIR" (EC8 / AC 14). Adding a real `cp ... log.md ... $CTX` makes the count nonzero; redirecting --add-dir to "$RUN_DIR" stops "read-root:context" printing.
phase: 12 · principal-delegate
owner: scripts/watcher.sh
