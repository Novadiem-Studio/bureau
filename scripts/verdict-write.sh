#!/bin/sh
# Validate a delegate verdict, enforce the revision cap, write the verdict file
# atomically, and append the ledger entry.
#
# This is the core bridge validator. On ANY validation failure (bad/invalid JSON,
# missing field, unreadable request, hash mismatch) — OR any verdict write/rename
# failure (full disk, unwritable target dir) — it prints the reason to stderr,
# fires notify-escalation.sh, exits 2, and writes NOTHING durable: no verdict file
# (not even a partial), no ledger entry. Write and ledger append are all-or-nothing:
# the ledger is appended ONLY after the verdict file is confirmed on disk. The
# verdict file is written ONLY via a tmp->rename (atomic; EC6); there is no other
# write path. Free-text fields are newline/control-char sanitized before render so
# a field value cannot inject an extra `key: value` line into the flat verdict file.
#
# Usage:
#   verdict-write.sh <raw-json> <request-file> <verdict-file> <ledger-file> \
#                    <run-dir> [revision-cap]
#
# Arguments:
#   <raw-json>       absolute path to the Delegate's raw JSON output
#   <request-file>   absolute path to the matching NN-request.md
#   <verdict-file>   absolute path to where NN-verdict.md should be written
#   <ledger-file>    absolute path to RUN_DIR/delegate-decisions.md
#   <run-dir>        absolute path to RUN_DIR (for the escalation notifier)
#   [revision-cap]   revision cap integer; default 2
#
# Exit codes:
#   0  verdict written + ledger appended
#   2  validation failure (no verdict written, no ledger appended; notifier fired)
#   1  bad arguments
#
# Spec refs: docs/delegate-bridge.md § 2, § 6; AC 8, AC 10, AC 16; EC2, EC6, EC7, EC10.
# Key invariants (gated at review):
#   - The cap is checked against revise-count from the REQUEST file — never against
#     `attempt`, never from the JSON output. A hash-rebind re-issue bumps `attempt`
#     but carries the same revise-count and must NOT trip the cap (EC7).
#   - The verdict file is written ONLY via $3.tmp -> mv. No code path writes it
#     without tmp->rename.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: verdict-write.sh <raw-json> <request-file> <verdict-file> <ledger-file> <run-dir> [revision-cap]" >&2
  exit 1
}

# ── argument handling ────────────────────────────────────────────────────────

[ "$#" -ge 5 ] || usage

RAW_JSON="$1"
REQUEST_FILE="$2"
VERDICT_FILE="$3"
LEDGER_FILE="$4"
RUN_DIR="$5"
CAP="${6:-2}"

for a in "$RAW_JSON" "$REQUEST_FILE" "$VERDICT_FILE" "$LEDGER_FILE" "$RUN_DIR"; do
  [ -n "$a" ] || usage
done

case "$CAP" in
  *[!0-9]* | '')
    echo "verdict-write: revision-cap must be a non-negative integer: $CAP" >&2
    exit 1
    ;;
esac

# Derive the checkpoint label NN for the notifier: basename of the verdict file,
# strip the -verdict.md suffix, strip leading zeros (05 -> 5; 00 -> 0).
NN_RAW="$(basename "$VERDICT_FILE")"
NN_RAW="${NN_RAW%-verdict.md}"
NN_LABEL="$(printf '%s' "$NN_RAW" | sed 's/^0*\([0-9]\)/\1/')"
[ -n "$NN_LABEL" ] || NN_LABEL="$NN_RAW"

# ── validation-failure helper ────────────────────────────────────────────────
# Prints the reason, fires the escalation notifier, exits 2. Writes NO verdict
# file and appends NO ledger entry.

fail() {
  reason="$1"
  echo "verdict-write: validation failure: $reason" >&2
  sh "$SCRIPT_DIR/notify-escalation.sh" "$NN_LABEL" "$RUN_DIR" "validation failure: $reason" || true
  exit 2
}

# ── step 1+2: parse + validate the 7 JSON fields ─────────────────────────────
# python3 is always present (jq may not be). python validates the JSON and that
# all 7 fields are present and non-empty, then emits one `NAME=base64value` line
# per field. base64 makes the values safe to carry through `eval` regardless of
# embedded newlines, spaces, or shell metacharacters. python exits non-zero on
# bad JSON or any missing/empty field; we route that to the validation-failure
# path.

[ -f "$RAW_JSON" ] || fail "raw JSON file not found: $RAW_JSON"

PARSED="$(python3 - "$RAW_JSON" <<'PY'
import base64, json, sys
path = sys.argv[1]
# (json key, shell var name)
fields = [
    ("Decision", "DECISION"),
    ("Artifact-hash", "ARTIFACT_HASH_JSON"),
    ("Uncertainties", "UNCERTAINTIES"),
    ("Rationale", "RATIONALE"),
    ("Required-changes", "REQUIRED_CHANGES"),
    ("Escalation", "ESCALATION"),
    ("Ledger", "LEDGER"),
]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as e:
    sys.stderr.write("bad JSON: %s\n" % e)
    sys.exit(3)
if not isinstance(data, dict):
    sys.stderr.write("JSON is not an object\n")
    sys.exit(3)
for key, _ in fields:
    v = data.get(key)
    if v is None or (isinstance(v, str) and v.strip() == ""):
        sys.stderr.write("missing or empty field: %s\n" % key)
        sys.exit(4)
# The verdict .md and the ledger are flat, line-oriented (one `key: value` per
# line). A free-text field value carrying an embedded newline/CR (or other
# control char) would inject an extra line — e.g. a second `decision:` line —
# that spoofs any line-grep consumer and defeats the file-level cap-rewrite
# guarantee. Collapse all control chars to a single space here so EVERY
# downstream use (verdict render AND ledger-append args) is clean.
def sanitize(s):
    return "".join(" " if (ord(c) < 0x20 or ord(c) == 0x7f) else c for c in s)
for key, var in fields:
    enc = base64.b64encode(sanitize(str(data[key])).encode("utf-8")).decode("ascii")
    sys.stdout.write("%s=%s\n" % (var, enc))
PY
)" || fail "JSON parse/validation failed (see stderr above)"

# Decode each NAME=base64 line back into a shell variable. Each line is
# `VAR=base64` with no internal spaces, so default IFS word-splitting on the
# newline-separated $PARSED is safe.
for line in $PARSED; do
  var="${line%%=*}"
  b64="${line#*=}"
  val="$(printf '%s' "$b64" | base64 --decode 2>/dev/null || printf '%s' "$b64" | base64 -d 2>/dev/null)"
  eval "$var=\$val"
done

# ── step 3: read the request file's four keys ────────────────────────────────
# artifact-hash:, revise-count:, checkpoint:, attempt:. The verdict file's
# checkpoint/attempt come from the request, not the JSON.

[ -f "$REQUEST_FILE" ] || fail "request file not found: $REQUEST_FILE"
[ -r "$REQUEST_FILE" ] || fail "request file not readable: $REQUEST_FILE"

req_field() {
  # Grep the first matching "key: value" line; strip the key and surrounding space.
  grep -E "^$1:[[:space:]]*" "$REQUEST_FILE" 2>/dev/null \
    | head -n 1 \
    | sed -E "s/^$1:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

REQ_HASH="$(req_field 'artifact-hash')"
REQ_REVISE_COUNT="$(req_field 'revise-count')"
REQ_CHECKPOINT="$(req_field 'checkpoint')"
REQ_ATTEMPT="$(req_field 'attempt')"
# artifact: (path) is parsed too — the ledger's OQ4 path field needs it. Match
# the `artifact:` key but NOT `artifact-hash:` (anchor on `artifact:` + space/EOL).
REQ_ARTIFACT="$(grep -E '^artifact:[[:space:]]*' "$REQUEST_FILE" 2>/dev/null | head -n 1 | sed -E 's/^artifact:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"

[ -n "$REQ_HASH" ] || fail "request file missing artifact-hash:"
[ -n "$REQ_REVISE_COUNT" ] || fail "request file missing revise-count:"
[ -n "$REQ_CHECKPOINT" ] || fail "request file missing checkpoint:"
[ -n "$REQ_ATTEMPT" ] || fail "request file missing attempt:"

case "$REQ_REVISE_COUNT" in
  *[!0-9]* | '') fail "request revise-count is not an integer: $REQ_REVISE_COUNT" ;;
esac

# ── step 4: hash check (EC2) ─────────────────────────────────────────────────

if [ "$ARTIFACT_HASH_JSON" != "$REQ_HASH" ]; then
  fail "hash mismatch — verdict discarded"
fi

# ── step 5: revision cap check (FR 35 / EC7) ─────────────────────────────────
# The cap is checked against revise-count from the REQUEST file — never against
# `attempt`, never from the JSON. Only Decision=revise AND revise-count >= cap
# rewrites the decision to escalate. A hash-rebind (bumped attempt, same
# revise-count) does NOT trip the cap.

DECISION_OUT="$DECISION"
if [ "$DECISION" = "revise" ] && [ "$REQ_REVISE_COUNT" -ge "$CAP" ]; then
  echo "verdict-write: revise-count cap reached — rewriting decision to escalate" >&2
  DECISION_OUT="escalate"
  # The original Escalation field may say "none"; record the cap as the reason.
  if [ -z "$ESCALATION" ] || [ "$ESCALATION" = "none" ]; then
    ESCALATION="revision cap reached (revise-count=$REQ_REVISE_COUNT >= cap=$CAP)"
  fi
fi

# ── step 6: write the verdict file ATOMICALLY (EC6) ──────────────────────────
# The ONLY write path for the verdict file: $3.tmp -> mv. checkpoint and attempt
# come from the REQUEST file.
#
# Fail-closed: the write must be all-or-nothing with the ledger append. If the
# render or the rename fails (full disk, unwritable dir, target dir removed),
# we must NOT append the ledger — that would mark the checkpoint decided with no
# verdict file and corrupt the append-only ledger. On any failure: remove the
# leftover tmp, route through the SAME fail() path (fire the notifier, exit 2,
# NO ledger append). The ledger append (step 7) happens ONLY after the verdict
# file is confirmed on disk.

TMPF="${VERDICT_FILE}.tmp"

# Helper: clean up the tmp file, then take the standard fail-closed path.
write_fail() {
  rm -f "$TMPF" 2>/dev/null || true
  fail "$1"
}

if ! cat >"$TMPF" <<EOF
checkpoint:       ${REQ_CHECKPOINT}
attempt:          ${REQ_ATTEMPT}
artifact-hash:    ${ARTIFACT_HASH_JSON}
decision:         ${DECISION_OUT}
uncertainties:    ${UNCERTAINTIES}
rationale:        ${RATIONALE}
required-changes: ${REQUIRED_CHANGES}
escalation:       ${ESCALATION}
ledger:           ${LEDGER}
EOF
then
  write_fail "could not render verdict tmp file: $TMPF"
fi

if ! mv "$TMPF" "$VERDICT_FILE"; then
  write_fail "could not rename verdict tmp into place: $VERDICT_FILE"
fi

# Confirm the verdict file is actually on disk before we let the ledger append.
[ -f "$VERDICT_FILE" ] || write_fail "verdict file missing after rename: $VERDICT_FILE"

# ── step 7: append the ledger entry ──────────────────────────────────────────
# Label is NN.A from the request (checkpoint.attempt). borderline = yes if the
# (possibly rewritten) decision is escalate, or if Uncertainties is non-trivial
# (any text other than "none"/empty).

LABEL="${REQ_CHECKPOINT}.${REQ_ATTEMPT}"

BORDERLINE="no"
if [ "$DECISION_OUT" = "escalate" ]; then
  BORDERLINE="yes"
else
  unc_trim="$(printf '%s' "$UNCERTAINTIES" | tr '[:upper:]' '[:lower:]')"
  case "$unc_trim" in
    "" | none) BORDERLINE="no" ;;
    *) BORDERLINE="yes" ;;
  esac
fi

# refs (bridge § 9) is `<notary review path | none>`, NOT the escalation reason
# (which already lives in the verdict file's `escalation:` line). No notary
# pointer exists at this stage, so it is always `none`.
sh "$SCRIPT_DIR/ledger-append.sh" \
  "$LEDGER_FILE" \
  "$LABEL" \
  "$DECISION_OUT" \
  "${REQ_ARTIFACT:-unknown}" \
  "$ARTIFACT_HASH_JSON" \
  "$UNCERTAINTIES" \
  "$RATIONALE" \
  "$BORDERLINE" \
  "none"

# ── step 8: escalation notification ──────────────────────────────────────────

if [ "$DECISION_OUT" = "escalate" ]; then
  sh "$SCRIPT_DIR/notify-escalation.sh" "$NN_LABEL" "$RUN_DIR" "$ESCALATION" || true
fi

# ── step 9: success ──────────────────────────────────────────────────────────

exit 0
