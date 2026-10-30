#!/bin/sh
# risk-coverage.sh — prove a bureau-lite build scanned every commit and reviewed every flag.
#
# scripts/risk-tags.sh decides per unit whether a cold review is needed, but the Conductor
# runs it and routes on its exit code. This check is the part the Conductor does not grade:
# scripts/integration-gate.sh runs it at every integration checkpoint of a run that uses
# bureau-lite and records it as the `risk-coverage` gate, so the Delegate's existing gate
# verdict enforces it (workflows/bureau-lite.md step 10); the close-out runs it again on the
# final head (step 11, and preflight-artifacts.sh --phase final).
#
# It walks the run branch's first-parent history from the anchor to the end point and requires:
#   1. Chain — every commit sits in a risk-tags record's base..head range, records linking
#      head-to-base with no gap. A merge commit needs no record only when every non-first
#      parent is already on the base branch (state.json#git.base_branch); any other merge is
#      a gap, since it can bring in code no record scanned.
#   2. Re-scan — every record is re-scanned here with the default config and the
#      run's policy ref; its result and tags must match what the record says. A record edited
#      after the fact, or scanned with a looser config or project block, fails.
#   3. Review — every record whose result is review, error or escalate has, after the
#      record's `at`, a SPAWN-EVENT in log.md with role challenger (or critic),
#      `"status":"complete"` and attempt_id `challenger-unit-<unit>-<n>`. A `review` record may
#      instead be covered by a log heading `## [<ts>] — RISK-TAGS waiver: unit <unit> ...`
#      dated after the record. An `escalate` record needs the review AND, after the record,
#      a `WORKFLOW-SHIFT: bureau-lite to execute-plan` heading and matching state entry.
#      A waiver cannot resume lite dispatch after an escalation.
#
# Records are RUN_DIR/risk-tags/<unit>.json, plus <unit>+<k>.json for follow-up scans.
#
# Anchor and end: for a run started as bureau-lite, from state.json#git.base_sha. For a run
# that shifted to bureau-lite (state.json#workflow_shifts), from the base of the record named
# by that shift's effective_from. If a later shift moves the run off bureau-lite, the chain
# ends at that shift's `head` (the HEAD sha when it was made); otherwise at --head.
# Every lite interval is checked, even after further upshifts and downshifts.
# A WORKFLOW-SHIFT heading to bureau-lite in log.md that state.json does not record is an
# error, so a missing state entry cannot turn the check off.
#
# Usage:
#   scripts/risk-coverage.sh <RUN_DIR> [--state <state.json>] [--worktree <path>] [--head <ref>]
#     [--project-context <path>] [--out <file>]
#
#   --state  the run's state file; default <RUN_DIR>/state.json.
#
# Exit codes (stdout carries one JSON line; --out gets the same record):
#   0  covered, or not applicable (the run never used bureau-lite)
#   1  not covered — a gap, a re-scan mismatch, or a flagged record without its review/decision
#   2  setup error — unreadable state.json, no anchor, no worktree, an unreadable record,
#      a log/state disagreement about a shift, a dirty worktree for the re-scan
#
# Deps: POSIX sh + python3 + git.

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$HERE/.." && pwd)/config/risk-tags.json"
RISK_TAGS="$HERE/risk-tags.sh"
RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] && shift
WORKTREE=""
HEAD_REF="HEAD"
PROJECT_CONTEXT=""
OUT=""
STATE=""
while [ "$#" -gt 0 ]; do
  if [ "$#" -lt 2 ]; then echo "risk-coverage: flag $1 needs a value" >&2; exit 2; fi
  case "$1" in
    --state)           STATE="$2";           shift 2 ;;
    --worktree)        WORKTREE="$2";        shift 2 ;;
    --head)            HEAD_REF="$2";        shift 2 ;;
    --project-context) PROJECT_CONTEXT="$2"; shift 2 ;;
    --out)             OUT="$2";             shift 2 ;;
    *) echo "risk-coverage: unknown flag: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "usage: risk-coverage.sh <RUN_DIR> [--worktree <path>] [--head <ref>] [--project-context <path>] [--out <file>]" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "risk-coverage: python3 not found" >&2; exit 2; }

[ -n "$STATE" ] || STATE="$RUN_DIR/state.json"

python3 - "$RUN_DIR" "$WORKTREE" "$HEAD_REF" "$OUT" "$CONFIG" "$RISK_TAGS" "$PROJECT_CONTEXT" "$STATE" <<'PY'
import glob
import json
import os
import re
import subprocess
import sys

run_dir, worktree, head_ref, out_path, config_path, risk_tags, project_context, state_path = sys.argv[1:9]
EXIT = {"covered": 0, "not_applicable": 0, "not_covered": 1, "error": 2}
rec = {"schema": 2, "result": None, "anchor": None, "end": None, "records": 0,
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


HEADING = re.compile(r"^## \[([^\]]+)\] — (.*)$", re.M)
SHIFT = re.compile(r"^WORKFLOW-SHIFT:\s*(\S+)\s+to\s+(\S+)")
WAIVER = re.compile(r"^RISK-TAGS waiver: unit (\S+?)[;:,\s]")


def main():
    global worktree
    try:
        with open(state_path) as fh:
            state = json.load(fh)
    except (OSError, ValueError) as e:
        raise Fail("state.json unreadable: %s" % e)
    try:
        with open(os.path.join(run_dir, "log.md")) as fh:
            log = fh.read()
    except OSError:
        log = ""
    headings = [(m.group(1), m.group(2)) for m in HEADING.finditer(log)]

    shifts = [s for s in (state.get("workflow_shifts") or []) if isinstance(s, dict)]
    lite_idx = max([i for i, s in enumerate(shifts) if s.get("to") == "bureau-lite"], default=None)
    logged_lite = sum(1 for _, h in headings if SHIFT.match(h) and SHIFT.match(h).group(2) == "bureau-lite")
    recorded_lite = sum(1 for s in shifts if s.get("to") == "bureau-lite")
    if logged_lite > recorded_lite:
        raise Fail("log.md records %d WORKFLOW-SHIFT headings to bureau-lite but state.json#workflow_shifts records %d"
                   % (logged_lite, recorded_lite))
    if state.get("workflow") != "bureau-lite" and lite_idx is None:
        rec["coverage"] = "REVIEW-COVERAGE: not applicable (run never used bureau-lite)"
        finish("not_applicable")

    git_block = state.get("git") or {}
    worktree = worktree or git_block.get("worktree_path") or ""
    if not worktree or not os.path.isdir(worktree):
        raise Fail("no worktree (pass --worktree, or set state.json#git.worktree_path)")

    def git(*args):
        return subprocess.run(["git", "-C", worktree] + list(args), capture_output=True, text=True, errors="replace")

    def resolve(ref):
        r = git("rev-parse", "--verify", "--quiet", str(ref) + "^{commit}")
        if r.returncode != 0 or not r.stdout.strip():
            raise Fail("cannot resolve %r" % ref)
        return r.stdout.strip()

    records = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "risk-tags", "*.json"))):
        name = os.path.basename(path)[:-5]
        try:
            with open(path) as fh:
                r = json.load(fh)
        except (OSError, ValueError) as e:
            raise Fail("record %s unreadable: %s" % (name, e))
        if not isinstance(r, dict):
            raise Fail("record %s is not an object" % name)
        r["_name"], r["_unit"] = name, name.split("+", 1)[0]
        records[name] = r
    rec["records"] = len(records)

    segments = []
    active = state.get("workflow")
    start_idx = None
    for idx, shift in enumerate(shifts):
        target = shift.get("to")
        if not target:
            raise Fail("workflow shift has no destination")
        if active == "bureau-lite" and target != "bureau-lite":
            segments.append((start_idx, [shift]))
        elif active != "bureau-lite" and target == "bureau-lite":
            start_idx = idx
        active = target
    if active == "bureau-lite":
        segments.append((start_idx, []))

    def check_segment(lite_idx, later):
        # Anchor, policy ref and end point.
        if lite_idx is None:
            if not git_block.get("base_sha"):
                raise Fail("state.json#git.base_sha is not set; cannot anchor the chain")
            anchor = resolve(git_block["base_sha"])
        else:
            eff = str(shifts[lite_idx].get("effective_from", ""))
            if eff not in records:
                raise Fail("workflow_shifts names effective_from %r but risk-tags/%s.json does not exist" % (eff, eff))
            anchor = resolve(records[eff].get("base"))
        if git_block.get("base_sha"):
            policy = resolve(git_block["base_sha"])
        elif lite_idx is not None and shifts[lite_idx].get("policy_ref"):
            policy = resolve(shifts[lite_idx]["policy_ref"])
        else:
            raise Fail("no policy ref: set state.json#git.base_sha or the shift's policy_ref")
        if later:
            if not later[0].get("head"):
                raise Fail("the shift off bureau-lite (to %r) has no head sha; cannot end the chain" % later[0].get("to"))
            end = resolve(later[0]["head"])
        else:
            end = resolve(head_ref)
        if rec["anchor"] is None:
            rec["anchor"] = anchor
        rec["end"] = end
        if git("merge-base", "--is-ancestor", anchor, end).returncode != 0:
            raise Fail("anchor %s is not an ancestor of %s" % (anchor[:12], end[:12]))

        base_branch = git_block.get("base_branch") or ""
        base_tips = []
        for cand in (base_branch, "origin/" + base_branch):
            if base_branch:
                r = git("rev-parse", "--verify", "--quiet", cand + "^{commit}")
                if r.returncode == 0 and r.stdout.strip():
                    base_tips.append(r.stdout.strip())

        # 1. Chain over first-parent history.
        commits = git("rev-list", "--first-parent", "--reverse", "%s..%s" % (anchor, end)).stdout.split()
        order = [anchor] + commits
        pos = {c: i for i, c in enumerate(order)}
        by_base = {}
        for r in records.values():
            by_base.setdefault(r.get("base"), []).append(r)
        i, used = 0, []
        while i < len(order) - 1:
            cur = order[i]
            cands = [r for r in by_base.get(cur, []) if r.get("head") in pos and pos[r["head"]] > i]
            if cands:
                r = max(cands, key=lambda x: pos[x["head"]])
                r = dict(r)
                r["_upshift"] = later[0] if later else None
                used.append(r)
                i = pos[r["head"]]
                continue
            nxt = order[i + 1]
            parents = git("rev-list", "--parents", "-n", "1", nxt).stdout.split()[1:]
            if len(parents) >= 2:
                side = parents[1:]
                if base_tips and all(any(git("merge-base", "--is-ancestor", p, tip).returncode == 0
                                         for tip in base_tips) for p in side):
                    i += 1
                    continue
                rec["problems"].append("gap: merge %s brings in commits not on the base branch %r and no record scans it"
                                       % (nxt[:12], base_branch))
                i += 1
                continue
            stop = i + 1
            while stop < len(order) - 1 and order[stop] not in by_base:
                stop += 1
            rec["problems"].append("gap: commits %s..%s are in no risk-tags record" % (cur[:12], order[stop][:12]))
            i = stop

        # 2. Re-scan every chained record with the default config and the run's policy.
        if git("status", "--porcelain").stdout.strip():
            raise Fail("worktree is dirty; commit or remove changes so records can be re-scanned")
        for r in used:
            cmd = [risk_tags, "--worktree", worktree, "--base", r["base"], "--head", r["head"],
                   "--policy-ref", policy, "--config", config_path]
            if project_context:
                cmd += ["--project-context", project_context]
            p = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
            try:
                fresh = json.loads(p.stdout.strip().splitlines()[-1])
            except (ValueError, IndexError):
                rec["problems"].append("record %s could not be re-scanned (exit %d)" % (r["_name"], p.returncode))
                continue
            want = (fresh.get("result"), sorted(fresh.get("review_tags", []) + fresh.get("escalate_tags", [])))
            got = (r.get("result"), sorted((r.get("review_tags") or []) + (r.get("escalate_tags") or [])))
            if fresh.get("result") == "error" or p.returncode not in (0, 1, 3):
                rec["problems"].append("record %s re-scan failed; repair and replace the record" % r["_name"])
            if want != got:
                rec["problems"].append("record %s says %s %s but a re-scan with the run's policy gives %s %s"
                                       % (r["_name"], got[0], got[1], want[0], want[1]))
                r["result"] = fresh.get("result")  # judge the review requirement on the truth

        return used
    used = []
    for lite_idx, later in segments:
        used.extend(check_segment(lite_idx, later))

    # 3. Review and decision evidence.
    reviews = {}
    for m in re.finditer(r"^SPAWN-EVENT:\s*(\{.*\})\s*$", log, re.M):
        try:
            ev = json.loads(m.group(1))
        except ValueError:
            continue
        if not isinstance(ev, dict) or ev.get("status") != "complete" or ev.get("role") not in ("challenger", "critic"):
            continue
        am = re.match(r"^(challenger|critic)-unit-(.+)-\d+$", str(ev.get("attempt_id", "")))
        if am:
            reviews.setdefault(am.group(2), []).append(str(ev.get("at", "")))
    waivers, heavier = {}, []
    for ts, h in headings:
        w = WAIVER.match(h)
        if w:
            waivers.setdefault(w.group(1), []).append(ts)
        s = SHIFT.match(h)
        if s and s.group(1) == "bureau-lite" and s.group(2) == "execute-plan":
            heavier.append(ts)

    counts = {"clean": 0, "reviewed": 0, "waived": 0, "escalated": 0, "error": 0}
    for r in used:
        unit, res, at = r["_unit"], r.get("result"), str(r.get("at", ""))
        rec["units"].setdefault(unit, []).append({"record": r["_name"], "result": res,
                                                  "tags": (r.get("escalate_tags") or []) + (r.get("review_tags") or [])})
        if res == "clean":
            counts["clean"] += 1
            continue
        reviewed = any(t >= at for t in reviews.get(unit, []))
        waived = any(t >= at for t in waivers.get(unit, []))
        if res == "escalate":
            counts["escalated"] += 1
            decided = bool(r.get("_upshift") and r["_upshift"].get("to") == "execute-plan"
                           and any(t >= at for t in heavier))
            if not reviewed:
                rec["problems"].append("record %s is escalate but no complete challenger-unit-%s-N review follows it" % (r["_name"], unit))
            if not decided:
                rec["problems"].append("record %s is escalate but no later WORKFLOW-SHIFT heading and state entry record Robin's decision to upshift to execute-plan" % r["_name"])
            if reviewed:
                counts["reviewed"] += 1
            continue
        if res == "error":
            counts["error"] += 1
        if reviewed:
            counts["reviewed"] += 1
        elif res == "review" and waived:
            counts["waived"] += 1
        else:
            rec["problems"].append("record %s is %s but no complete challenger-unit-%s-N review follows it%s"
                                   % (r["_name"], res, unit, " (and no later waiver)" if res == "review" else ""))
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
