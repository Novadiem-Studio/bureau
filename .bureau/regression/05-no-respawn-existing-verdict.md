name: Watcher skips a request that already has a verdict (static source guard)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Static guard: watcher.sh must skip a request whose NN-verdict.md already
  # exists (FR 38). Grep its source for the skip-if-verdict guard.
  SCRIPT=$ROOT/scripts/watcher.sh
  grep -q -- '-verdict.md' "$SCRIPT" && \
  grep -Fq '[ -f "$verdict_file" ]' "$SCRIPT" && \
  echo "skip-if-verdict-present"
expected: prints "skip-if-verdict-present" — watcher.sh references NN-verdict.md and tests `[ -f "$verdict_file" ]` before re-spawning (both greps exit 0)
phase: 12 · principal-delegate
owner: scripts/watcher.sh
