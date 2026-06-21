name: Bundle 09 — launcher self-locates ROOT + validates --max-usd + arms trap early
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Static guard on delegate-launcher.sh robustness. MUTATION-HARDENED: every grep
  # runs against the script with COMMENT LINES STRIPPED, so a guarantee that
  # survives only in a comment cannot satisfy it. The header AND the explanatory
  # note near the end ("No second `trap teardown TERM INT` needed") both mention
  # `trap teardown TERM INT`; stripping comments means only the real armed trap
  # (line ~138) can satisfy the trap clause. Likewise --max-usd appears in the
  # usage/help comments; only the real `--max-usd)` argument-parse arm counts.
  L=$ROOT/scripts/delegate-launcher.sh
  # Strip full-line comments AND inline trailing comments, leaving only code.
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  strip "$L" | grep -Eq 'ROOT=.*SCRIPT_DIR' && \
  ! strip "$L" | grep -Eq 'export ROOT="/' && \
  strip "$L" | grep -q 'max-usd' && \
  strip "$L" | grep -Eq 'trap teardown TERM INT' && \
  echo LAUNCHER-ROBUST-OK
expected: prints "LAUNCHER-ROBUST-OK" — in real (non-comment) code: ROOT is derived from SCRIPT_DIR (not hardcoded canonical), --max-usd is parsed/validated, and the teardown trap is armed. Deleting the real `trap teardown TERM INT`, hardcoding ROOT, or removing --max-usd each fails the guard even though the comments still mention them.
phase: 11 · execute-plan
owner: prompts.md Prompt 11 (scripts/delegate-launcher.sh)
