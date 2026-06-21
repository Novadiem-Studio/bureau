#!/bin/sh
# Fire a desktop notification for a delegate escalation.
#
# On notification failure (Linux, CI, notification daemon down, or osascript
# absent) it writes a local fallback file and warns. It NEVER aborts the
# caller's loop: exit 0 in both the success and the failure path (EC4 / A2 / FR 7).
#
# Usage:
#   notify-escalation.sh <checkpoint-id> <run-dir> <reason>
#
# Arguments:
#   <checkpoint-id>   checkpoint id (e.g. 05)
#   <run-dir>         absolute path to RUN_DIR (where the fallback file is written)
#   <reason>          one-line escalation reason (quote it)
#
# Exit codes:
#   0  always (success path AND failure path) — never aborts the caller
#   1  bad arguments only
#
# Spec refs: docs/delegate-bridge.md § 8 (escalation channel); EC4, A2, FR 7.

usage() {
  echo "Usage: notify-escalation.sh <checkpoint-id> <run-dir> <reason>" >&2
  exit 1
}

# ── argument handling ────────────────────────────────────────────────────────

[ "$#" -eq 3 ] || usage

CP="$1"
RUN_DIR="$2"
REASON="$3"

[ -n "$CP" ] || usage
[ -n "$RUN_DIR" ] || usage
[ -n "$REASON" ] || usage

# ── try the desktop notification ─────────────────────────────────────────────

notify_ok=1
if command -v osascript >/dev/null 2>&1; then
  if osascript -e "display notification \"Delegate escalation: checkpoint ${CP} — ${REASON}\" with title \"Agent Framework\"" >/dev/null 2>&1; then
    notify_ok=0
  fi
fi

if [ "$notify_ok" -eq 0 ]; then
  exit 0
fi

# ── fallback: write ESCALATION-NN.md, warn, exit 0 ───────────────────────────
# Ensure the checkpoints dir exists before writing.

CHECKPOINTS_DIR="$RUN_DIR/checkpoints"
FALLBACK_FILE="$CHECKPOINTS_DIR/ESCALATION-${CP}.md"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$CHECKPOINTS_DIR"

cat >"$FALLBACK_FILE" <<EOF
# ESCALATION — checkpoint ${CP}

- timestamp: ${TIMESTAMP}
- reason: ${REASON}

A delegate verdict escalated. The desktop notification could not be delivered,
so this file is the fallback channel. The loop is holding — respond by writing
${RUN_DIR}/checkpoints/${CP}-robin.md.
EOF

echo "Notification failed — wrote ${FALLBACK_FILE}" >&2
exit 0
