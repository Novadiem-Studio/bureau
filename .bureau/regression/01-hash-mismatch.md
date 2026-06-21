name: Hash mismatch verdict discarded
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  echo 'artifact-hash: aaaa1111' > "$TMPDIR/01-request.md"
  echo 'revise-count: 0' >> "$TMPDIR/01-request.md"
  echo 'checkpoint: 01' >> "$TMPDIR/01-request.md"
  echo 'attempt: 1' >> "$TMPDIR/01-request.md"
  echo '{"Decision":"proceed","Artifact-hash":"bbbb2222","Uncertainties":"none","Rationale":"ok","Required-changes":"none","Escalation":"none","Ledger":"01.1"}' \
    > "$TMPDIR/01.delegate-out.json"
  "$ROOT/scripts/verdict-write.sh" \
    "$TMPDIR/01.delegate-out.json" \
    "$TMPDIR/01-request.md" \
    "$TMPDIR/01-verdict.md" \
    "$TMPDIR/delegate-decisions.md" \
    "$TMPDIR" 2; echo "exit:$?"
  test -f "$TMPDIR/01-verdict.md" && echo "verdict:present" || echo "verdict:absent"
  test -f "$TMPDIR/delegate-decisions.md" && echo "ledger:present" || echo "ledger:absent"
expected: prints "exit:2", "verdict:absent", and "ledger:absent" — hash mismatch fails closed (no verdict file, no ledger entry)
phase: 12 · principal-delegate
owner: scripts/verdict-write.sh
