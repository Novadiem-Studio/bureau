name: Bundle 15 P4 — integration executor extracted to integration-gate.sh (non-tautological ff, --detach base-ref, canonical regression runner); watcher.sh calls it + keeps frozen §3 spawn
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  W="$ROOT/scripts/watcher.sh"
  G="$ROOT/scripts/integration-gate.sh"
  R="$ROOT/scripts/run-cold-reviewer.sh"
  # Bundle 15 P4: watcher.sh's inline integration executor was EXTRACTED to
  # scripts/integration-gate.sh (one copy, two callers — the v1 watcher + the v2
  # Delegate; bridge v2 §5). The executor-body assertions (non-tautological ff
  # check, --detach base-ref worktree, canonical regression runner) therefore now
  # target integration-gate.sh; watcher.sh keeps only the request-field parse
  # (REQ_CHECKPOINT_TYPE), the gate CALL, and the frozen §3 spawn (--tools "Read",
  # no Bash grant). A literal $ in a pattern is matched via the proven escaped-ERE
  # form carried over verbatim from the pre-extraction fixture.
  bash -n "$W" || { echo "watcher.sh syntax error"; exit 1; }
  bash -n "$G" || { echo "integration-gate.sh syntax error"; exit 1; }
  # watcher still parses checkpoint-type (to build the gate's CLI flags + task override)
  grep -q 'REQ_CHECKPOINT_TYPE' "$W" || { echo "watcher checkpoint-type parse missing"; exit 1; }
  # watcher delegates to the extracted gate executor instead of running it inline
  grep -q 'integration-gate.sh' "$W" || { echo "watcher does not call integration-gate.sh"; exit 1; }
  # executor logic now lives in integration-gate.sh:
  # non-tautological fast-forward check (base-ref first operand, HEAD second)
  grep -Eq 'merge-base --is-ancestor "\$REQ_BASE_REF" HEAD' "$G" || { echo "ff check missing/tautological in gate"; exit 1; }
  # base-ref temp worktree must be detached (works when base branch is checked out elsewhere)
  grep -Eq 'worktree add --detach' "$G" || { echo "base-ref worktree add not --detach in gate"; exit 1; }
  # canonical gate set must NOT be derived from claimed-gates (provenance, FR-B14-14)
  grep -q 'regression/run.sh' "$G" || { echo "canonical regression runner not referenced in gate"; exit 1; }
  # frozen Claude §3 invocation moved intact to the provider-neutral helper
  grep -Eq -- '--tools "Read"' "$R" || { echo "frozen --tools Read missing"; exit 1; }
  grep -Eq -- '--tools "(Read,)?Bash' "$R" && { echo "Bash tool grant leaked into spawn"; exit 1; }
  echo PASS
expected: exit 0 — prints PASS; nonzero if watcher.sh no longer parses checkpoint-type or calls integration-gate.sh, if the gate executor loses its verification guards, or if a Bash grant leaks into the helper's frozen Claude reviewer spawn.
phase: 03 · execute-plan (Bundle 14); repointed 2b · execute-plan (Bundle 15 P4 extraction)
owner: scripts/watcher.sh + scripts/integration-gate.sh + scripts/run-cold-reviewer.sh
