#!/bin/sh
# Await a delegate verdict file.
#
# The Conductor's re-invocation primitive. Run via the Bash tool with
# run_in_background: true. The script sleep-loops until the verdict file appears,
# then exits 0 — which fires the single completion notification that re-invokes
# the Conductor. Zero model tokens are consumed while it waits.
#
# Usage:
#   await-verdict.sh <verdict-file-path> [timeout-seconds]
#
# Arguments:
#   <verdict-file-path>   absolute path to the verdict file to wait for
#   [timeout-seconds]     positive integer; default 600
#
# Exit codes:
#   0  the verdict file appeared within the timeout
#   2  timed out waiting for the verdict file
#   1  bad arguments
#
# Spec refs: docs/delegate-bridge.md § 5 (Conductor checkpoint shim); FR 2, FR 37.

usage() {
  echo "Usage: await-verdict.sh <verdict-file-path> [timeout-seconds]" >&2
  exit 1
}

# ── argument handling ────────────────────────────────────────────────────────

VERDICT_FILE="$1"
[ -n "$VERDICT_FILE" ] || usage

TIMEOUT="${2:-600}"

# Validate timeout is a positive integer (digits only, not zero).
case "$TIMEOUT" in
  *[!0-9]* | '')
    echo "await-verdict: timeout must be a positive integer: $TIMEOUT" >&2
    exit 1
    ;;
esac
[ "$TIMEOUT" -gt 0 ] || {
  echo "await-verdict: timeout must be a positive integer: $TIMEOUT" >&2
  exit 1
}

# ── wait loop ────────────────────────────────────────────────────────────────

echo "Waiting for verdict: $VERDICT_FILE (timeout: ${TIMEOUT}s)"

# Poll resolution is 2s (the sleep step below), so the effective timeout rounds
# up to the next 2s boundary (e.g. a 5s timeout fires at ~6s).
elapsed=0
until [ -f "$VERDICT_FILE" ]; do
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "Timeout waiting for verdict: $VERDICT_FILE" >&2
    exit 2
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "Verdict appeared: $VERDICT_FILE"
exit 0
