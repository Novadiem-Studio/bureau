#!/bin/sh
# ledger-set-robins-call.sh — deterministic `Robin's call:` population (W6 / AC14).
#
# On an escalation RESOLUTION, the v2 Delegate fills the blank `Robin's call:` line
# for the resolved record with Robin's literal answer. The model never hand-edits
# the append-only ledger (delegate-decisions.md): this one-shot locates the blank
# field for record NN and fills only that line, touching nothing else, so the
# append-only invariant stays a SCRIPT guarantee rather than an instruction (FR10).
#
# Usage:
#   ledger-set-robins-call.sh <NN> "<literal value>"
#
# Record identification: a ledger record (docs/delegate-bridge/watcher-v1.md § Section 9) is a block
# that begins at a `## NN.<attempt> — <timestamp>` header (ledger-append.sh:67) and
# runs until the next `## ` header or EOF. ledger-append.sh writes ONE record per
# verdict, each with a `decision:` line (ledger-append.sh:68) and a blank
# `Robin's call:` line — INCLUDING revise records. So NN alone is ambiguous on the
# revise->escalate cap path (records `NN.1` decision:revise + `NN.2` decision:escalate
# both carry a blank `Robin's call:`). `Robin's call:` ONLY ever resolves an
# ESCALATION, so the target is the record for NN whose `decision:` field is
# `escalate`; revise records' blank lines are never filled and stay blank. A blank
# field is `Robin's call:` with nothing after the colon (what ledger-append.sh writes).
#
# Behavior:
#   1. Resolve the ledger path (see "Ledger path" below).
#   2. Find the record block for NN whose `decision:` is `escalate`.
#   3. Fill only that record's blank `Robin's call:` line with the literal value.
#   4. Touch NO other line (atomic tmp -> mv; every other byte preserved).
#
# Exit codes:
#   0  the blank field was filled
#   1  any error: no unresolved escalation record for NN, the field is already
#      filled (refuse to overwrite), >1 escalation record (defensive), bad args,
#      or a write failure
#
# Ledger path:
#   $LEDGER_FILE wins if set; else $RUN_DIR/delegate-decisions.md; else error.
#   Prefer explicit ($LEDGER_FILE) — the caller always knows the path.
#
# Deps: POSIX sh + python3. Callers: the v2 Delegate (manager mode), on resolution.

if [ "$#" -ne 2 ]; then
  echo "Usage: ledger-set-robins-call.sh <NN> \"<literal value>\"" >&2
  exit 1
fi

NN="$1"
VALUE="$2"

if [ -n "$LEDGER_FILE" ]; then
  LEDGER="$LEDGER_FILE"
elif [ -n "$RUN_DIR" ]; then
  LEDGER="$RUN_DIR/delegate-decisions.md"
else
  echo "ledger-set-robins-call: set \$LEDGER_FILE (preferred) or \$RUN_DIR" >&2
  exit 1
fi

python3 - "$LEDGER" "$NN" "$VALUE" <<'PY'
import os, re, sys

ledger, nn, value = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(ledger) as fh:
        text = fh.read()
except OSError as e:
    sys.stderr.write("ledger-set-robins-call: cannot read ledger: %s\n" % e)
    sys.exit(1)

# Split into lines but preserve the exact byte layout on re-join: read().split("\n")
# round-trips through "\n".join (a trailing newline becomes a trailing "" element).
lines = text.split("\n")

# Header `## NN.<attempt> — …` is the canonical record locator (the `decision:` field
# picks the right verdict among NN's records). No `checkpoint:` matcher: real records
# carry no such field, and a body cross-reference to another NN must not over-select.
header_re    = re.compile(r'^##\s+' + re.escape(nn) + r'[.\s]')
decision_re  = re.compile(r'^decision:\s*(\S+)')
robins_any   = re.compile(r"^Robin's call:")
robins_blank = re.compile(r"^Robin's call:\s*$")

# Index record blocks by their `## ` headers.
header_idxs = [i for i, l in enumerate(lines) if l.startswith("## ")]
blocks = []
for k, start in enumerate(header_idxs):
    end = header_idxs[k + 1] if k + 1 < len(header_idxs) else len(lines)
    blocks.append((start, end))

# Select the record for NN whose `decision:` is `escalate`. revise/proceed records
# for the same NN also carry a blank `Robin's call:`, but they are NOT resolved here.
escalate_blocks = []
for (start, end) in blocks:
    if not header_re.match(lines[start]):
        continue
    decision = None
    for j in range(start, end):
        m = decision_re.match(lines[j])
        if m:
            decision = m.group(1).lower()
            break
    if decision == "escalate":
        escalate_blocks.append((start, end))

if len(escalate_blocks) == 0:
    sys.stderr.write("ledger-set-robins-call: no unresolved escalation record for checkpoint %s\n" % nn)
    sys.exit(1)
if len(escalate_blocks) > 1:
    sys.stderr.write("ledger-set-robins-call: multiple escalation records for %s — refusing (defensive)\n" % nn)
    sys.exit(1)

# Locate that record's single Robin's call line.
start, end = escalate_blocks[0]
robins_idx = None
for j in range(start, end):
    if robins_any.match(lines[j]):
        robins_idx = j
        break
if robins_idx is None:
    sys.stderr.write("ledger-set-robins-call: escalation record for %s has no Robin's call line\n" % nn)
    sys.exit(1)
if not robins_blank.match(lines[robins_idx]):
    sys.stderr.write("ledger-set-robins-call: Robin's call already filled for %s — refusing to overwrite\n" % nn)
    sys.exit(1)

# Fill ONLY the target line; every other line is preserved verbatim.
lines[robins_idx] = "Robin's call:  " + value

tmp = ledger + ".tmp"
try:
    with open(tmp, "w") as fh:
        fh.write("\n".join(lines))
    os.replace(tmp, ledger)
except OSError as e:
    sys.stderr.write("ledger-set-robins-call: atomic write failed: %s\n" % e)
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.exit(1)

sys.exit(0)
PY
