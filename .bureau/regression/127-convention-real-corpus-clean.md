name: C0 — real-corpus zero-false-positive guard (Check h; guards against Check-f regression)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  cat >"$WORK/spec.md" <<'SPECEOF'
  ## Architecture

  Backticked-symbol reuse lines (must NOT fire — these are correctly-cited reuses):
  supersede reuses the existing `appendSupersede` function to merge nodes.
  reuses the existing `ingest_one` pipeline for deduplication.

  Conceptual reuse lines with no backtick (must NOT fire — legitimate conceptual reuse;
  a future Check-f block demanding path:Symbol would wrongly fire on these):
  reuses the existing memory-block merge pattern for consistency.
  Reuse the existing seam for the hook attachment.

  Negation line (must NOT fire):
  do NOT reuse `snapshotFreshness` for this path — the semantics differ.

  Narrowing-lock negatives for Check-h (compound terms without adjacent backtick — must NOT fire):
  the pattern table lists all matching role pairs in the system.
  `counter` is already incremented by the background saga runner.

  Conforming convention line with explicit no-CLAUDE.md escape (must NOT fire):
  The `accepted` store slice — no CLAUDE.md for bureau sub-app — convention applied from novadiem-engineering § Reuse-first pattern.
  SPECEOF
  touch "$WORK/plan.md"
  out="$("$ROOT/scripts/preflight-artifacts.sh" "$WORK" --phase round1)"
  echo "$out"
  echo "$out" | grep -qx 'preflight: clean' || { echo "FAIL: expected 'preflight: clean', got: $out"; exit 1; }
expected: exit 0, stdout contains exactly `preflight: clean` (asserted by inline grep -qx)
phase: Prompt 3 · feature (20260708-semantic-producer-checks)
owner: check_convention_citations + no-Check-f-regression — retire only if both (a) Check h is removed AND (b) the real-corpus lines above are no longer representative
