name: A leftover .tmp file is not treated as the verdict
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  # A crash can leave 07-verdict.md.tmp behind. The atomic tmp->rename contract
  # means a .tmp is NOT the verdict — await-verdict.sh waits for 07-verdict.md.
  touch "$TMPDIR/07-verdict.md.tmp"
  "$ROOT/scripts/await-verdict.sh" \
    "$TMPDIR/07-verdict.md" 3; echo "exit:$?"
expected: prints "exit:2" — the presence of 07-verdict.md.tmp does not satisfy the wait; await-verdict.sh times out and exits 2 (EC6)
phase: 12 · principal-delegate
owner: scripts/await-verdict.sh
