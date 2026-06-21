name: await-verdict.sh timeout exits 2
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  "$ROOT/scripts/await-verdict.sh" \
    "$TMPDIR/nonexistent-verdict.md" 3; echo "exit:$?"
expected: prints "exit:2" — await-verdict.sh exits 2 after the ~4s timeout (no verdict file ever appears; no auto-proceed, FR 37)
phase: 12 · principal-delegate
owner: scripts/await-verdict.sh
