#!/bin/sh
# Generate the run-end delegate summary from the decision ledger.
#
# Parses ONLY delegate-decisions.md — never log.md, never the artifact set. The
# work is O(n) on the checkpoint count (EC5): one pass over the ledger records,
# no re-reading of run files. Each ledger record is the schema ledger-append.sh
# writes (docs/delegate-bridge.md § 9); this script is the read side of that
# contract.
#
# Usage:
#   summary-gen.sh <ledger-file> <output-file>
#
# Arguments:
#   <ledger-file>   absolute path to RUN_DIR/delegate-decisions.md
#   <output-file>   absolute path to RUN_DIR/delegate-summary.md
#
# Exit codes:
#   0  summary written
#   1  bad arguments, or the ledger file does not exist
#
# Spec refs: docs/delegate-bridge.md § 9 (ledger schema); AC 15, FR 8, EC5.

usage() {
  echo "Usage: summary-gen.sh <ledger-file> <output-file>" >&2
  exit 1
}

# ── argument handling ────────────────────────────────────────────────────────

[ "$#" -eq 2 ] || usage

LEDGER_FILE="$1"
OUTPUT_FILE="$2"

[ -n "$LEDGER_FILE" ] || usage
[ -n "$OUTPUT_FILE" ] || usage

if [ ! -f "$LEDGER_FILE" ]; then
  echo "summary-gen: ledger file not found: $LEDGER_FILE" >&2
  exit 1
fi

# ── parse the ledger + render the summary (python3; always present) ───────────
# python is used for the parse because each record is multi-line and the grouping
# is more robust than sed/awk. It reads ONLY the ledger path passed as argv[1]
# and writes ONLY argv[2]; it opens no other file. A record begins at a line of
# the form `## NN.A — <timestamp>`; the fields that follow are flat `key: value`
# lines (`Robin's call:` may be blank). Unknown/extra lines are ignored.

python3 - "$LEDGER_FILE" "$OUTPUT_FILE" <<'PY'
import datetime
import re
import sys

ledger_path, out_path = sys.argv[1], sys.argv[2]

# A record header: "## 05.2 — 2026-06-21T08:52:05Z"  (em dash or hyphen separator).
header_re = re.compile(r'^##\s+(\S+)\s+[—-]\s+(.*)$')

records = []
cur = None
with open(ledger_path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        m = header_re.match(line)
        if m:
            if cur is not None:
                records.append(cur)
            cur = {"label": m.group(1).strip(), "timestamp": m.group(2).strip()}
            continue
        if cur is None:
            continue
        # Flat "key: value" field lines. Split on the FIRST colon only so a
        # value containing a colon (e.g. a path) survives intact.
        if ":" in line:
            key, _, val = line.partition(":")
            cur[key.strip().lower()] = val.strip()
    if cur is not None:
        records.append(cur)

def field(rec, name, default=""):
    return rec.get(name, default)

proceed = [r for r in records if field(r, "decision") == "proceed"]
revise = [r for r in records if field(r, "decision") == "revise"]
escalate = [r for r in records if field(r, "decision") == "escalate"]
borderline = [r for r in records if field(r, "borderline").lower() == "yes"]

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def truncate(s, n=80):
    s = s.replace("|", "\\|")
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"

out = []
out.append("# Delegate Run Summary — %s" % now)
out.append("")
out.append("Proceed: %d | Revise: %d | Escalate: %d"
           % (len(proceed), len(revise), len(escalate)))
out.append("")

# ── Escalations ──────────────────────────────────────────────────────────────
out.append("## Escalations")
out.append("")
if not escalate:
    out.append("None.")
else:
    for r in escalate:
        out.append("### %s — %s" % (field(r, "label"), field(r, "timestamp")))
        out.append("- artifact: %s" % field(r, "artifact", "unknown"))
        out.append("- rationale: %s" % field(r, "rationale"))
        rc = field(r, "robin's call")
        out.append("- Robin's call: %s" % (rc if rc else "(unresolved)"))
        out.append("")
    out.pop()  # drop the trailing blank line
out.append("")

# ── Borderline calls ─────────────────────────────────────────────────────────
out.append("## Borderline calls")
out.append("")
if not borderline:
    out.append("None.")
else:
    for r in borderline:
        out.append("- %s (%s): %s"
                   % (field(r, "label"),
                      field(r, "decision"),
                      field(r, "rationale")))
out.append("")

# ── All decisions ────────────────────────────────────────────────────────────
out.append("## All decisions")
out.append("")
out.append("| NN.A | decision | rationale |")
out.append("|------|----------|-----------|")
for r in records:
    out.append("| %s | %s | %s |"
               % (field(r, "label"),
                  field(r, "decision"),
                  truncate(field(r, "rationale"))))
out.append("")

with open(out_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
PY

exit 0
