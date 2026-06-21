name: Hash-rebind (attempt bumped, same revise-count) does not trip the cap
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  # POSIX 64-hex hash (no xxd, no Bash brace): exactly matches schema ^[a-f0-9]{64}$
  HASH=$(printf 'a%.0s' $(seq 64))
  # revise-count=1 (below default cap=2), attempt=3 (two prior hash-rebinds).
  # The cap is counted against revise-count, NOT attempt, so this must NOT escalate.
  echo "artifact-hash: $HASH" > "$TMPDIR/11-request.md"
  echo 'revise-count: 1' >> "$TMPDIR/11-request.md"
  echo 'checkpoint: 11' >> "$TMPDIR/11-request.md"
  echo 'attempt: 3' >> "$TMPDIR/11-request.md"
  printf '{"Decision":"revise","Artifact-hash":"%s","Uncertainties":"thin","Rationale":"needs fix","Required-changes":"architecture","Escalation":"none","Ledger":"11.3"}' "$HASH" \
    > "$TMPDIR/11.delegate-out.json"
  "$ROOT/scripts/verdict-write.sh" \
    "$TMPDIR/11.delegate-out.json" "$TMPDIR/11-request.md" \
    "$TMPDIR/11-verdict.md" "$TMPDIR/delegate-decisions.md" "$TMPDIR" 2
  grep -E '^decision:[[:space:]]+revise' "$TMPDIR/11-verdict.md" && echo "revise-preserved"
expected: prints "decision:         revise" then "revise-preserved" — revise-count=1 < cap=2, so the verdict stays revise despite attempt=3 (grep exits 0, EC7)
phase: 12 · principal-delegate
owner: scripts/verdict-write.sh
