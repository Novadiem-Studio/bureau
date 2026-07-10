#!/bin/sh
# Append one timestamped section to a run's log.md with a REAL, shell-computed UTC
# stamp — so the Conductor (an LLM) can never fabricate a plausible-looking time
# from context. The timestamp comes ONLY from `date -u`, never from an argument.
#
# Why this exists: the Conductor writes log.md entries as text and, being a language
# model, TYPES a plausible `## [TIMESTAMP]` from its head instead of reading a clock —
# so planning-run logs drift to round-hour placeholders and wall-clock / human-wait
# become unmeasurable. This helper makes the clock read MECHANICAL: a shell computes
# the time every call, and the same stamp is echoed for reuse on adjacent event lines.
#
# Usage:
#   log-append.sh <RUN_DIR> "<heading text>"      # append "## [<TS>] — <heading>", echo <TS>
#   log-append.sh <RUN_DIR> "<heading text>" < body   # body piped on stdin, appended verbatim
#   log-append.sh --now                            # print a fresh <TS> only; write nothing
#
# Behavior:
#   - TS is always `date -u +%Y-%m-%dT%H:%M:%SZ` (real UTC, this instant).
#   - Appends "\n## [<TS>] — <heading>\n" to <RUN_DIR>/log.md, creating it if absent,
#     appending (never truncating) if present.
#   - If a body is piped on stdin (non-tty), it is appended verbatim under the heading.
#   - Echoes <TS> to stdout so the caller can reuse the SAME real stamp for an adjacent
#     machine event-line "at" field (the header and the event line share one clock read).
#   - `--now` (or no RUN_DIR) prints only a fresh `date -u` stamp — a real-clock primitive
#     for stamping an "at" field without writing a heading.
#
# Exit codes:
#   0  section appended (or --now stamp printed)
#   1  bad arguments (missing/again-not-a-dir RUN_DIR, or empty heading)
#
# POSIX /bin/sh; portable to macOS /bin/sh and Bash 3.2. No bashisms.

usage() {
  echo "Usage: log-append.sh <RUN_DIR> \"<heading text>\" [< body]   |   log-append.sh --now" >&2
  exit 1
}

# The ONE clock read. Every timestamp in this script — heading and echoed stamp — is
# this single value, so a header and its adjacent event line share one real read.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── --now / no-args mode: print a fresh real stamp, write nothing ──────────────
if [ "$#" -eq 0 ] || [ "$1" = "--now" ]; then
  printf '%s\n' "$TS"
  exit 0
fi

# ── argument handling ─────────────────────────────────────────────────────────

[ "$#" -eq 2 ] || usage

RUN_DIR="$1"
HEADING="$2"

case "$RUN_DIR" in
  /*) ;;
  *)  echo "log-append: RUN_DIR must be an absolute path, got: $RUN_DIR" >&2; usage ;;
esac
[ -d "$RUN_DIR" ] || { echo "log-append: RUN_DIR does not exist or is not a directory: $RUN_DIR" >&2; usage; }
[ -n "$HEADING" ] || { echo "log-append: heading text must be non-empty" >&2; usage; }

LOG_FILE="$RUN_DIR/log.md"

# ── append (never overwrite) ──────────────────────────────────────────────────
# A leading blank line separates this section from prior content; harmless on the
# first write. `>>` creates the file if absent and appends otherwise — never `>`.
{
  printf '\n## [%s] — %s\n' "$TS" "$HEADING"
  # Append a piped body verbatim only when stdin is NOT a tty (something was piped).
  if [ ! -t 0 ]; then
    cat
  fi
} >>"$LOG_FILE"

# Echo the SAME real stamp for reuse on an adjacent event-line "at" field.
printf '%s\n' "$TS"
exit 0
