#!/bin/sh
# revise-cap.sh — deterministic revision-cap enforcement (W-c / FR11 / AC15).
#
# The SINGLE authoritative revise counter is delegate-state.json#revise_counts[NN]
# (W-a). On a `revise` verdict the v2 Delegate calls this one-shot, which atomically
# increments revise_counts[NN] and emits the cap decision to stdout:
#   escalate  — when the NEW count reaches (>=) the cap;
#   revise    — otherwise.
# The Delegate acts on this stdout, never on its own cap inference. This restores
# v1 verdict-write.sh's SCRIPT guarantee ("rewrite to escalate at cap regardless of
# what the Delegate emitted") so the cap is a script guarantee, not a model
# instruction (AC15). The Conductor's return block carries no counter (OQ2/W5), so
# the cap can neither fire early nor never.
#
# Usage:
#   revise-cap.sh <delegate-state.json-path> <NN> <cap>
#
# Behavior:
#   1. Read delegate-state.json at the given path.
#   2. Read revise_counts[NN] (0 if absent).
#   3. Increment revise_counts[NN] by 1.
#   4. Write the updated JSON atomically (tmp -> mv), so concurrent calls cannot
#      corrupt the file.
#   5. Print "escalate" if the new count >= cap, else "revise".
#
# Exit codes:
#   0  success (a cap decision was printed and the file was updated)
#   1  any error (file not found, invalid JSON, non-integer cap, write failure)
#
# Deps: POSIX sh + python3 — exactly what watcher.sh already requires; no new deps.
# Callers: the v2 Delegate (manager mode), on a `revise` verdict.

if [ "$#" -ne 3 ]; then
  echo "Usage: revise-cap.sh <delegate-state.json-path> <NN> <cap>" >&2
  exit 1
fi

STATE="$1"
NN="$2"
CAP="$3"

# python3 does the read/increment/atomic-write; the script exits with its status.
python3 - "$STATE" "$NN" "$CAP" <<'PY'
import json, os, sys

state_path, nn, cap_raw = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    cap = int(cap_raw)
except (ValueError, TypeError):
    sys.stderr.write("revise-cap: cap is not an integer: %r\n" % cap_raw)
    sys.exit(1)

try:
    with open(state_path) as fh:
        data = json.load(fh)
except FileNotFoundError:
    sys.stderr.write("revise-cap: delegate-state.json not found: %s\n" % state_path)
    sys.exit(1)
except (ValueError, OSError) as e:
    sys.stderr.write("revise-cap: cannot read delegate-state.json: %s\n" % e)
    sys.exit(1)

if not isinstance(data, dict):
    sys.stderr.write("revise-cap: delegate-state.json is not a JSON object\n")
    sys.exit(1)

counts = data.get("revise_counts")
if not isinstance(counts, dict):
    counts = {}

try:
    current = int(counts.get(nn, 0))
except (ValueError, TypeError):
    current = 0

new = current + 1
counts[nn] = new
data["revise_counts"] = counts

# Atomic write: render to a sibling .tmp then os.replace (atomic on the same fs).
tmp = state_path + ".tmp"
try:
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, state_path)
except OSError as e:
    sys.stderr.write("revise-cap: atomic write failed: %s\n" % e)
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.exit(1)

print("escalate" if new >= cap else "revise")
sys.exit(0)
PY
