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
# Record identification: a ledger record (docs/delegate-bridge.md § 9) is a block
# that begins at a `## NN.A — <timestamp>` header and runs until the next `## `
# header or EOF. The record for NN is matched by that header's ordinal (`## NN.`),
# and ALSO by a `checkpoint: NN` field if one is present (belt-and-suspenders for
# any future record shape). The blank line is `Robin's call:` with nothing after
# the colon (exactly what ledger-append.sh writes); a filled field has a value.
#
# Behavior:
#   1. Resolve the ledger path (see "Ledger path" below).
#   2. Find the record block for NN.
#   3. Fill only its blank `Robin's call:` line with the literal value.
#   4. Touch NO other line (atomic tmp -> mv; every other byte preserved).
#
# Exit codes:
#   0  the blank field was filled
#   1  any error: no record for NN, the field is already filled (refuse to
#      overwrite), an ambiguous set of blank fields, bad args, or a write failure
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

header_re     = re.compile(r'^##\s+' + re.escape(nn) + r'[.\s]')
checkpoint_re = re.compile(r'^checkpoint:\s*' + re.escape(nn) + r'\s*$')
robins_any    = re.compile(r"^Robin's call:")
robins_blank  = re.compile(r"^Robin's call:\s*$")

# Index record blocks by their `## ` headers.
header_idxs = [i for i, l in enumerate(lines) if l.startswith("## ")]
blocks = []
for k, start in enumerate(header_idxs):
    end = header_idxs[k + 1] if k + 1 < len(header_idxs) else len(lines)
    blocks.append((start, end))

# Select the blocks that ARE record NN.
target_blocks = []
for (start, end) in blocks:
    if header_re.match(lines[start]) or any(checkpoint_re.match(lines[j]) for j in range(start, end)):
        target_blocks.append((start, end))

if not target_blocks:
    sys.stderr.write("ledger-set-robins-call: no record found for checkpoint %s\n" % nn)
    sys.exit(1)

# Within the NN record(s), find the (single) blank Robin's call line.
blank_idxs = []
filled_seen = False
for (start, end) in target_blocks:
    for j in range(start, end):
        if robins_any.match(lines[j]):
            if robins_blank.match(lines[j]):
                blank_idxs.append(j)
            else:
                filled_seen = True
            break  # one Robin's call line per record

if len(blank_idxs) == 0:
    if filled_seen:
        sys.stderr.write("ledger-set-robins-call: Robin's call already filled for %s — refusing to overwrite\n" % nn)
    else:
        sys.stderr.write("ledger-set-robins-call: no blank Robin's call line for %s\n" % nn)
    sys.exit(1)
if len(blank_idxs) > 1:
    sys.stderr.write("ledger-set-robins-call: multiple blank Robin's call lines for %s — ambiguous, refusing\n" % nn)
    sys.exit(1)

# Fill ONLY the target line; every other line is preserved verbatim.
lines[blank_idxs[0]] = "Robin's call:  " + value

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
