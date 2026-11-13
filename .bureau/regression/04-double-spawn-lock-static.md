name: watcher.sh double-spawn lock implementation present (static source guard)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Static source guard, NOT a bare-mkdir tautology. A behavioral double-spawn
  # test needs a live `claude` spawn, so this objectively guards the locking
  # LOGIC in watcher.sh: it fails if the atomic mkdir claim or the dead-PID
  # reclaim is removed. MUTATION-HARDENED: both greps run against the script with
  # COMMENT LINES STRIPPED, so the `kill -0` reclaim cannot be satisfied by the
  # header/inline comments that mention it (e.g. the `kill -0` mention in the
  # pid_alive doc comment) — the reclaim must exist in real code.
  SCRIPT=$ROOT/scripts/watcher.sh
  # Strip full-line comments AND inline trailing comments, leaving only code.
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  # 1. The atomic per-request lock claim: `mkdir "$lock_dir"` (fixed string — contains a literal $)
  strip "$SCRIPT" | grep -Fq 'mkdir "$lock_dir"' && \
  # 2. The dead-PID reclaim that lets a crashed watcher's lock be re-taken: `kill -0`
  strip "$SCRIPT" | grep -q 'kill -0' && \
  # 3. The O_EXCL pid write that decides the race when mkdir cannot (uutils mkdir, #131)
  strip "$SCRIPT" | grep -Fq 'set -C; echo "$$" > "$lock_dir/pid"' && \
  echo "lock-guard-present"
expected: prints "lock-guard-present" — watcher.sh's real (non-comment) code contains the `mkdir "$lock_dir"` claim, the `kill -0` dead-PID reclaim, and the noclobber (`set -C`) pid write that makes the claim exclusive where mkdir is not (Rust coreutils mkdir on Ubuntu 26.04 can report success to two racers, issue #131). Deleting any of the three from the code fails the guard even though the header comments still mention them.
phase: 12 · principal-delegate
owner: scripts/watcher.sh
