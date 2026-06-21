name: Revision cap rewrite to escalate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  # POSIX 64-hex hash (no xxd, no Bash brace): exactly matches schema ^[a-f0-9]{64}$
  HASH=$(printf 'a%.0s' $(seq 64))
  echo "artifact-hash: $HASH" > "$TMPDIR/03-request.md"
  echo 'revise-count: 2' >> "$TMPDIR/03-request.md"
  echo 'checkpoint: 03' >> "$TMPDIR/03-request.md"
  echo 'attempt: 3' >> "$TMPDIR/03-request.md"
  printf '{"Decision":"revise","Artifact-hash":"%s","Uncertainties":"needs work","Rationale":"incomplete","Required-changes":"architecture","Escalation":"none","Ledger":"03.3"}' "$HASH" \
    > "$TMPDIR/03.delegate-out.json"
  "$ROOT/scripts/verdict-write.sh" \
    "$TMPDIR/03.delegate-out.json" "$TMPDIR/03-request.md" \
    "$TMPDIR/03-verdict.md" "$TMPDIR/delegate-decisions.md" "$TMPDIR" 2
  grep -E '^decision:[[:space:]]+escalate' "$TMPDIR/03-verdict.md" && echo "cap-rewrote-to-escalate"
expected: prints "decision:         escalate" then "cap-rewrote-to-escalate" — Decision=revise at revise-count=2 (cap=2) is rewritten to escalate (grep exits 0)
phase: 12 · principal-delegate
owner: scripts/verdict-write.sh
