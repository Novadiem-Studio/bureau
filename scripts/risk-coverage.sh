#!/bin/sh
# risk-coverage.sh — prove a bureau-lite build scanned every commit and reviewed every flag.
#
# scripts/risk-tags.sh decides per unit whether a cold review is needed, but the Conductor
# runs it and routes on its exit code. This check is the part the Conductor does not grade:
# the Delegate runs it at every integration checkpoint and stages its record for the cold
# reviewer (workflows/bureau-lite.md step 10), and the close-out runs it again (step 11).
#
# It walks the run branch's first-parent history from the anchor to HEAD and requires:
#   1. Chain — every commit sits in exactly one risk-tags record's base..head range. Records
#      link head-to-base with no gap and no overlap. A gap made only of merge commits is
#      allowed (the post-merge integration gate covers a base-branch merge).
#   2. Policy — every record ran on the default config (same sha256 as
#      <framework>/config/risk-tags.json now) with policy_ref equal to the anchor's policy ref,
#      so no record used a loosened tag list or a project block the run itself rewrote.
#   3. Review — every record whose result is review, error or escalate has, AFTER the
#      record's `at`, a terminal `"status":"complete"` SPAWN-EVENT in log.md for the
#      Challenger with attempt_id `challenger-unit-<unit>-<n>` (or `critic-unit-...`).
#      A `review` record may instead be covered by a `RISK-TAGS waiver: unit <unit>` line
#      (Robin's call, logged by the session he spoke to); escalate and error records may not.
#
# Records are RUN_DIR/risk-tags/<unit>.json, plus <unit>+<k>.json for a follow-up scan of
# fix commits made after a unit's first scan. <unit> is the record's name before any "+".
#
# Anchor: state.json#git.base_sha for a run started as bureau-lite. For a run that shifted to
# bureau-lite (state.json#workflow_shifts, last shift to "bureau-lite"), the base of the
# record named by that shift's effective_from; the chain is checked from there.
#
# Usage:
#   scripts/risk-coverage.sh <RUN_DIR> [--worktree <path>] [--head <ref>] [--out <file>]
#
# Exit codes (stdout carries one JSON line; --out gets the same record):
#   0  covered (or not applicable: the run never used bureau-lite)
#   1  not covered — a gap, a policy mismatch, or a flagged record with no review
#   2  setup error — unreadable state.json, no anchor, no worktree, an unreadable record
#
# Deps: POSIX sh + python3 + git.

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$HERE/.." && pwd)/config/risk-tags.json"
RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] && shift
WORKTREE=""
HEAD_REF="HEAD"
OUT=""
while [ "$#" -gt 0 ]; do
  if [ "$#" -lt 2 ]; then echo "risk-coverage: flag $1 needs a value" >&2; exit 2; fi
  case "$1" in
    --worktree) WORKTREE="$2"; shift 2 ;;
    --head)     HEAD_REF="$2"; shift 2 ;;
    --out)      OUT="$2";      shift 2 ;;
    *) echo "risk-coverage: unknown flag: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "usage: risk-coverage.sh <RUN_DIR> [--worktree <path>] [--head <ref>] [--out <file>]" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "risk-coverage: python3 not found" >&2; exit 2; }

python3 - "$RUN_DIR" "$WORKTREE" "$HEAD_REF" "$OUT" "$CONFIG" <<'PY'
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

run_dir, worktree, head_ref, out_path, config_path = sys.argv[1:6]
EXIT = {"covered": 0, "not_applicable": 0, "not_covered": 1, "error": 2}
rec = {"schema": 1, "result": None, "anchor": None, "head": None, "records": 0,
       "units": {}, "coverage": None, "problems": []}


def finish(result, error=None):
    rec["result"] = result
    if error:
        rec["error"] = error
    if out_path:
        try:
            with open(out_path, "w") as fh:
                fh.write(json.dumps(rec, indent=2, sort_keys=True) + "\n")
        except OSError as e:
            result, rec["result"], rec["error"] = "error", "error", "cannot write %s: %s" % (out_path, e)
    print(json.dumps(rec, sort_keys=True))
    if rec.get("coverage"):
        print(rec["coverage"], file=sys.stderr)
    for p in rec["problems"]:
        print("risk-coverage: " + p, file=sys.stderr)
    if result == "error":
        print("risk-coverage: error — %s" % rec.get("error"), file=sys.stderr)
    sys.exit(EXIT[result])


class Fail(Exception):
    pass


def main():
    global worktree
    try:
        with open(os.path.join(run_dir, "state.json")) as fh:
            state = json.load(fh)
    except (OSError, ValueError) as e:
        raise Fail("state.json unreadable: %s" % e)
    shifts = state.get("workflow_shifts") or []
    effective = shifts[-1].get("to") if shifts else state.get("workflow")
    lite_shift = None
    for s in shifts:
        if s.get("to") == "bureau-lite":
            lite_shift = s
    if state.get("workflow") != "bureau-lite" and lite_shift is None:
        rec["coverage"] = "REVIEW-COVERAGE: not applicable (run never used bureau-lite)"
        finish("not_applicable")
    git_block = state.get("git") or {}
    worktree = worktree or git_block.get("worktree_path") or ""
    if not worktree or not os.path.isdir(worktree):
        raise Fail("no worktree (pass --worktree, or set state.json#git.worktree_path)")

    def git(*args):
        return subprocess.run(["git", "-C", worktree] + list(args), capture_output=True, text=True, errors="replace")

    def resolve(ref):
        r = git("rev-parse", "--verify", "--quiet", ref + "^{commit}")
        if r.returncode != 0 or not r.stdout.strip():
            raise Fail("cannot resolve %r" % ref)
        return r.stdout.strip()

    # Records
    records = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "risk-tags", "*.json"))):
        name = os.path.basename(path)[:-5]
        try:
            with open(path) as fh:
                r = json.load(fh)
        except (OSError, ValueError) as e:
            raise Fail("record %s unreadable: %s" % (name, e))
        r["_name"] = name
        r["_unit"] = name.split("+", 1)[0]
        records[name] = r
    rec["records"] = len(records)

    # Anchor
    if state.get("workflow") == "bureau-lite" and lite_shift is None:
        if not git_block.get("base_sha"):
            raise Fail("state.json#git.base_sha is not set; cannot anchor the chain")
        anchor = resolve(git_block["base_sha"])
        policy_anchor = anchor
    else:
        eff = str(lite_shift.get("effective_from", ""))
        if eff not in records:
            raise Fail("workflow_shifts names effective_from %r but risk-tags/%s.json does not exist" % (eff, eff))
        anchor = resolve(records[eff]["base"])
        policy_anchor = resolve(git_block["base_sha"]) if git_block.get("base_sha") else records[eff].get("policy_ref")
    head = resolve(head_ref)
    rec["anchor"], rec["head"] = anchor, head
    if git("merge-base", "--is-ancestor", anchor, head).returncode != 0:
        raise Fail("anchor %s is not an ancestor of head %s" % (anchor[:12], head[:12]))

    try:
        with open(config_path, "rb") as fh:
            config_sha = hashlib.sha256(fh.read()).hexdigest()
    except OSError as e:
        raise Fail("default config unreadable: %s" % e)

    # 1. Chain over first-parent history
    commits = git("rev-list", "--first-parent", "--reverse", "%s..%s" % (anchor, head)).stdout.split()
    by_base = {}
    for r in records.values():
        by_base.setdefault(r.get("base"), []).append(r)
    order = [anchor] + commits
    pos = {c: i for i, c in enumerate(order)}
    i, used = 0, []
    while i < len(order) - 1:
        cur = order[i]
        cands = [r for r in by_base.get(cur, []) if r.get("head") in pos and pos[r["head"]] > i]
        if cands:
            r = max(cands, key=lambda x: pos[x["head"]])
            used.append(r)
            i = pos[r["head"]]
            continue
        nxt = order[i + 1]
        parents = git("rev-list", "--parents", "-n", "1", nxt).stdout.split()[1:]
        if len(parents) >= 2:
            i += 1
            continue
        # Unscanned commits: report the gap up to the next record base (or HEAD).
        end = i + 1
        while end < len(order) - 1 and order[end] not in by_base:
            end += 1
        rec["problems"].append("gap: commits %s..%s are in no risk-tags record" % (cur[:12], order[end][:12]))
        i = end
    unused = [r["_name"] for r in records.values() if r not in used and r.get("result") != "error"]
    for name in unused:
        if records[name].get("head") in pos or records[name].get("base") in pos:
            rec["problems"].append("record %s overlaps or does not link into the chain" % name)

    # 2. Policy
    for r in used:
        if r.get("result") == "error":
            continue
        if r.get("config_sha256") != config_sha:
            rec["problems"].append("record %s used a different tag list (config sha %s)" % (r["_name"], str(r.get("config_sha256"))[:12]))
        if policy_anchor and r.get("policy_ref") != policy_anchor:
            rec["problems"].append("record %s read its project policy from %s, not the run's start %s"
                                   % (r["_name"], str(r.get("policy_ref"))[:12], str(policy_anchor)[:12]))

    # 3. Review evidence
    try:
        with open(os.path.join(run_dir, "log.md")) as fh:
            log = fh.read()
    except OSError:
        log = ""
    reviews = {}
    for m in re.finditer(r"^SPAWN-EVENT:\s*(\{.*\})\s*$", log, re.M):
        try:
            ev = json.loads(m.group(1))
        except ValueError:
            continue
        if not isinstance(ev, dict) or ev.get("status") != "complete":
            continue
        am = re.match(r"^(challenger|critic)-unit-(.+)-\d+$", str(ev.get("attempt_id", "")))
        if am:
            reviews.setdefault(am.group(2), []).append(str(ev.get("at", "")))
    waived = set(re.findall(r"^.*RISK-TAGS waiver: unit (\S+?)[;:\s]", log, re.M))

    counts = {"clean": 0, "reviewed": 0, "waived": 0, "escalated": 0, "error": 0}
    for r in used:
        unit, res = r["_unit"], r.get("result")
        rec["units"].setdefault(unit, []).append({"record": r["_name"], "result": res, "tags": r.get("escalate_tags", []) + r.get("review_tags", [])})
        if res == "clean":
            counts["clean"] += 1
            continue
        after = [at for at in reviews.get(unit, []) if at >= str(r.get("at", ""))]
        if res == "escalate":
            counts["escalated"] += 1
        if res == "error":
            counts["error"] += 1
        if after:
            counts["reviewed"] += 1
        elif res == "review" and unit in waived:
            counts["waived"] += 1
        else:
            rec["problems"].append("record %s is %s but no complete challenger-unit-%s-N SPAWN-EVENT follows it%s"
                                   % (r["_name"], res, unit, " (and no waiver)" if res == "review" else ""))
    rec["coverage"] = ("REVIEW-COVERAGE: %d records over %d units; clean %d; reviewed %d (escalated %d, error %d); waived %d; problems %d"
                       % (len(used), len(rec["units"]), counts["clean"], counts["reviewed"], counts["escalated"],
                          counts["error"], counts["waived"], len(rec["problems"])))
    finish("not_covered" if rec["problems"] else "covered")


try:
    main()
except Fail as e:
    finish("error", str(e))
except SystemExit:
    raise
except Exception as e:
    finish("error", "internal error: %s: %s" % (type(e).__name__, e))
PY
