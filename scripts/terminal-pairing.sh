#!/bin/sh
# terminal-pairing.sh — pair a terminal whole-PR cold review with the final gate (issue #92).
#
# At the terminal gate the Delegate or Envoy may spawn the whole-PR cold review
# while the final integration gate is still running, instead of after it. The
# review's verdict counts only when it pairs with a GREEN final gate on the SAME
# head SHA. This script is that pairing check, so it is a script guarantee, not a
# judgement: the caller records the SHA it handed the reviewer at spawn time and
# passes it here with the final gate's integration-results.json.
#
# Usage:
#   scripts/terminal-pairing.sh --gate <path/to/integration-results.json> \
#     --review-sha <40-hex sha the review saw> [--out <pairing.json>]
#
# Exit codes (stdout carries one JSON line either way; --out gets the same record):
#   0  paired — the gate is a green final gate and its branch_tip equals the review SHA.
#      The verdict counts.
#   1  discard — the final gate is not green (a red or pending-timeout gate, an
#      escalate marker, fast-forward/conflict failure, or not a final gate).
#      Discard the review uncounted and run the ordinary fix loop.
#   3  refused — the gate is green but verified a different SHA than the review
#      saw. Refuse the verdict; re-review (or re-gate) on one SHA.
#   2  usage error, or an unreadable results file.
#
# Deps: POSIX sh + python3.

GATE=""
REVIEW_SHA=""
OUT=""
while [ "$#" -gt 0 ]; do
  if [ "$#" -lt 2 ]; then
    echo "terminal-pairing: flag $1 needs a value" >&2
    exit 2
  fi
  case "$1" in
    --gate)       GATE="$2";       shift 2 ;;
    --review-sha) REVIEW_SHA="$2"; shift 2 ;;
    --out)        OUT="$2";        shift 2 ;;
    *) echo "terminal-pairing: unknown flag: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$GATE" ] || [ -z "$REVIEW_SHA" ]; then
  echo "terminal-pairing: --gate and --review-sha are required" >&2
  exit 2
fi

python3 - "$GATE" "$REVIEW_SHA" "$OUT" <<'PY'
import json, re, sys

gate_path, review_sha, out = sys.argv[1:4]
review_sha = review_sha.strip().lower()


def finish(code, status, reason, gate_sha=None, gate_green=False):
    record = {"status": status, "paired": code == 0, "reason": reason,
              "review_sha": review_sha, "gate_sha": gate_sha,
              "gate_green": gate_green, "gate_results": gate_path}
    line = json.dumps(record)
    print(line)
    if out:
        with open(out, "w") as fh:
            fh.write(line + "\n")
    sys.exit(code)


if not re.fullmatch(r"[0-9a-f]{40}", review_sha):
    sys.stderr.write("terminal-pairing: --review-sha must be a full 40-hex commit SHA\n")
    sys.exit(2)
try:
    with open(gate_path) as fh:
        g = json.load(fh)
    if not isinstance(g, dict):
        raise ValueError("not an object")
except Exception as e:
    sys.stderr.write("terminal-pairing: cannot read %s: %s\n" % (gate_path, e))
    sys.exit(2)

gate_sha = str(g.get("branch_tip") or "").strip().lower() or None
gates = g.get("gates") if isinstance(g.get("gates"), list) else []
problems = []
if g.get("escalate_marker"):
    problems.append("escalate marker: %s" % g["escalate_marker"])
if g.get("final_gate") is not True:
    problems.append("not a final gate (final_gate is not true)")
if g.get("gate_mode") not in ("ci", "local"):
    problems.append("no gate ran (gate_mode %r)" % g.get("gate_mode"))
if not gates:
    problems.append("no gate records")
red = [x.get("name", "?") for x in gates
       if not isinstance(x, dict) or x.get("exit_code_branch") != 0 or x.get("result") != "green"]
if red:
    problems.append("red gate(s): %s" % ", ".join(map(str, red)))
if g.get("fast_forward_ok") is not True:
    problems.append("fast_forward_ok is not true")
if g.get("conflicts_clean") is not True:
    problems.append("conflicts_clean is not true")
if gate_sha is None or not re.fullmatch(r"[0-9a-f]{40}", gate_sha):
    problems.append("gate recorded no usable branch_tip")
ci = g.get("ci") or {}
if g.get("gate_mode") == "ci" and str(ci.get("head_sha") or "").lower() != gate_sha:
    problems.append("CI head_sha does not match branch_tip")

if problems:
    finish(1, "discard", "final gate is not green: " + "; ".join(problems), gate_sha, False)
if gate_sha != review_sha:
    finish(3, "refused", "the review saw %s but the green final gate verified %s: a verdict counts only on the gate's SHA"
           % (review_sha[:12], gate_sha[:12]), gate_sha, True)
finish(0, "paired", "green final gate and review on the same head %s" % gate_sha[:12], gate_sha, True)
PY
