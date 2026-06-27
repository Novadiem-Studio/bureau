#!/bin/sh
# Append one decision record to the delegate decision ledger.
#
# Append-only (FR 26-28): never reads the existing file, never edits a prior
# entry, never maintains a rolling summary. Writes with >> (create-if-absent),
# never > (overwrite). Called by verdict-write.sh.
#
# Usage:
#   ledger-append.sh <ledger-file> <label> <decision> <artifact-path> \
#                    <artifact-hash> <uncertainties> <rationale> \
#                    <borderline> <refs>
#
# Arguments:
#   <ledger-file>     absolute path to RUN_DIR/delegate-decisions.md
#   <label>           checkpoint+attempt label, NN.A (e.g. 05.2)
#   <decision>        proceed | revise | escalate
#   <artifact-path>   absolute path to the artifact
#   <artifact-hash>   artifact SHA-256 hex
#   <uncertainties>   uncertainties text (quote it)
#   <rationale>       rationale text (quote it)
#   <borderline>      yes | no
#   <refs>            none, or a path (e.g. a notary review)
#
# Exit codes:
#   0  record appended
#   1  bad arguments
#
# Spec refs: docs/delegate-bridge/watcher-v1.md § Section 9 (decision ledger schema); FR 26-28.

usage() {
  echo "Usage: ledger-append.sh <ledger-file> <label> <decision> <artifact-path> <artifact-hash> <uncertainties> <rationale> <borderline> <refs>" >&2
  exit 1
}

# ── argument handling ────────────────────────────────────────────────────────

[ "$#" -eq 9 ] || usage

LEDGER_FILE="$1"
LABEL="$2"
DECISION="$3"
ARTIFACT_PATH="$4"
ARTIFACT_HASH="$5"
UNCERTAINTIES="$6"
RATIONALE="$7"
BORDERLINE="$8"
REFS="$9"

# All nine must be non-empty.
for arg_name in LEDGER_FILE LABEL DECISION ARTIFACT_PATH ARTIFACT_HASH UNCERTAINTIES RATIONALE BORDERLINE REFS; do
  eval "arg_val=\$$arg_name"
  if [ -z "$arg_val" ]; then
    echo "ledger-append: missing required argument: $arg_name" >&2
    usage
  fi
done

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── append (never overwrite) ─────────────────────────────────────────────────
# A leading blank line separates records when the file already has content;
# harmless on first write. The "Robin's call:" line is always blank here —
# it is populated later, on escalation resolution, not by this script.

cat >>"$LEDGER_FILE" <<EOF

## ${LABEL} — ${TIMESTAMP}
decision:      ${DECISION}
artifact:      ${ARTIFACT_PATH}
artifact-hash: ${ARTIFACT_HASH}
uncertainties: ${UNCERTAINTIES}
rationale:     ${RATIONALE}
borderline:    ${BORDERLINE}
refs:          ${REFS}
Robin's call:
EOF

exit 0
