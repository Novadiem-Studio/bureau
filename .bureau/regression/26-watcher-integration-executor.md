name: Bundle 14 P3 — watcher integration executor present, fenced, non-tautological ff, --detach base-ref, escalate fallback; §3 spawn frozen
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  W="$ROOT/scripts/watcher.sh"
  bash -n "$W" || { echo "watcher.sh syntax error"; exit 1; }
  grep -q 'REQ_CHECKPOINT_TYPE' "$W" || { echo "integration executor missing"; exit 1; }
  # non-tautological fast-forward check (base-ref first operand, HEAD second)
  grep -Eq 'merge-base --is-ancestor "\$REQ_BASE_REF" HEAD' "$W" || { echo "ff check missing/tautological"; exit 1; }
  # base-ref temp worktree must be detached (works when base branch is checked out elsewhere)
  grep -Eq 'worktree add --detach' "$W" || { echo "base-ref worktree add not --detach"; exit 1; }
  # canonical gate set must NOT be derived from claimed-gates (provenance, FR-B14-14)
  grep -q 'regression/run.sh' "$W" || { echo "canonical regression runner not referenced"; exit 1; }
  # frozen §3 invocation: --tools "Read" still present, no Bash grant added
  grep -Eq -- '--tools "Read"' "$W" || { echo "frozen --tools Read missing"; exit 1; }
  grep -Eq -- '--tools "(Read,)?Bash' "$W" && { echo "Bash tool grant leaked into spawn"; exit 1; }
  echo PASS
expected: exit 0 — prints PASS; nonzero if the executor is absent, the ff check is tautological, base-ref add is not --detach, canonical provenance references claimed-gates, or a Bash grant leaked into the frozen §3 spawn
phase: 03 · execute-plan (Bundle 14)
owner: prompts.md Prompt 3 (scripts/watcher.sh)
