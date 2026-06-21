name: Missing verdict field rejected
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  echo 'artifact-hash: aaaa1111' > "$TMPDIR/02-request.md"
  echo 'revise-count: 0' >> "$TMPDIR/02-request.md"
  echo 'checkpoint: 02' >> "$TMPDIR/02-request.md"
  echo 'attempt: 1' >> "$TMPDIR/02-request.md"
  # Missing Rationale field — must be rejected by verdict-write.sh
  echo '{"Decision":"proceed","Artifact-hash":"aaaa1111","Uncertainties":"none","Required-changes":"none","Escalation":"none","Ledger":"02.1"}' \
    > "$TMPDIR/02.delegate-out.json"
  "$ROOT/scripts/verdict-write.sh" \
    "$TMPDIR/02.delegate-out.json" \
    "$TMPDIR/02-request.md" \
    "$TMPDIR/02-verdict.md" \
    "$TMPDIR/delegate-decisions.md" \
    "$TMPDIR" 2; echo "exit:$?"
  test -f "$TMPDIR/02-verdict.md" && echo "verdict:present" || echo "verdict:absent"
  test -f "$TMPDIR/delegate-decisions.md" && echo "ledger:present" || echo "ledger:absent"
expected: prints "exit:2", "verdict:absent", and "ledger:absent" — a missing required field fails closed (no verdict file, no ledger entry)
phase: 12 · principal-delegate
owner: scripts/verdict-write.sh
