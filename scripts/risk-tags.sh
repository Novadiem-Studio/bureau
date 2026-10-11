#!/bin/sh
# risk-tags.sh — decide, mechanically, whether one build unit's diff needs a cold review.
#
# workflows/bureau-lite.md runs the per-unit cold build-diff Challenger only on units whose
# diff touches an enumerated risk surface (OAuth/auth, tokens and secrets, network egress,
# tool allowlists, redaction, migrations, irreversible sends, concurrency). Which units those
# are is decided here, by matching the diff's changed paths and changed lines against a fixed
# pattern list, never by the Conductor's reading of the diff. The Conductor may ADD a review
# this script did not ask for; it may not skip one this script did ask for.
#
# Usage:
#   scripts/risk-tags.sh --worktree <abs path> --base <ref> [--head <ref>] \
#     [--config <risk-tags.json>] [--project-context <path>] [--out <record.json>]
#
#   --worktree         the git worktree the unit was built in.
#   --base             the commit the unit started from (its parent; the diff is base...head).
#   --head             default HEAD.
#   --config           default <framework>/config/risk-tags.json.
#   --project-context  the project file whose ```json risk_tags``` block adds tags or
#                      patterns. Default: project-context.md as committed on --base, read
#                      with `git show`, so the run branch cannot loosen its own triggers.
#                      A project block may only ADD: new tags, extra patterns on an existing
#                      tag, or `"class": "escalate"` on an existing tag. It may not set
#                      ignore_paths, downgrade a class, or narrow a tag with line_scope.
#   --out              also write the record to this file.
#
# Exit codes (stdout carries one JSON line either way; --out gets the same record):
#   0  clean    — no tag fired. The unit ships on the coder's tests + CodeRabbit.
#   1  review   — one or more `review` tags fired and no `escalate` tag did.
#                 Run the cold build-diff Challenger on this unit.
#   3  escalate — an `escalate` tag fired (money, destructive migration). This is no longer
#                 a bureau-lite unit: stop and checkpoint.
#   2  error    — bad arguments, an unresolvable ref, an unreadable or invalid config or
#                 project block. Fail closed: the caller treats this as `review`.
#
# The record names files, line numbers and the pattern that matched. It never copies the
# matched line's text: a diff that trips `tokens-secrets` may carry a real secret, and the
# record lands in RUN_DIR.
#
# Deps: POSIX sh + python3 + git.

HERE="$(cd "$(dirname "$0")" && pwd)"
WORKTREE=""
BASE=""
HEAD_REF="HEAD"
CONFIG="$(cd "$HERE/.." && pwd)/config/risk-tags.json"
PROJECT_CONTEXT=""
OUT=""

while [ "$#" -gt 0 ]; do
  if [ "$#" -lt 2 ]; then
    echo "risk-tags: flag $1 needs a value" >&2
    exit 2
  fi
  case "$1" in
    --worktree)        WORKTREE="$2";        shift 2 ;;
    --base)            BASE="$2";            shift 2 ;;
    --head)            HEAD_REF="$2";        shift 2 ;;
    --config)          CONFIG="$2";          shift 2 ;;
    --project-context) PROJECT_CONTEXT="$2"; shift 2 ;;
    --out)             OUT="$2";             shift 2 ;;
    *) echo "risk-tags: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKTREE" ] || [ -z "$BASE" ]; then
  echo "usage: risk-tags.sh --worktree <path> --base <ref> [--head <ref>] [--config <file>] [--project-context <file>] [--out <file>]" >&2
  exit 2
fi

python3 - "$WORKTREE" "$BASE" "$HEAD_REF" "$CONFIG" "$PROJECT_CONTEXT" "$OUT" <<'PY'
import json
import re
import subprocess
import sys

worktree, base_ref, head_ref, config_path, project_context, out_path = sys.argv[1:7]
EXIT = {"clean": 0, "review": 1, "error": 2, "escalate": 3}
MAX_HITS_PER_TAG = 20

record = {
    "schema": 1,
    "result": None,
    "base": base_ref,
    "head": head_ref,
    "config": config_path,
    "project_source": None,
    "files_changed": 0,
    "files_scanned": 0,
    "files_ignored": [],
    "fired": [],
    "review_tags": [],
    "escalate_tags": [],
}


def finish(result, error=None):
    record["result"] = result
    if error:
        record["error"] = error
    line = json.dumps(record, sort_keys=True)
    if out_path:
        try:
            with open(out_path, "w") as fh:
                fh.write(json.dumps(record, indent=2, sort_keys=True) + "\n")
        except OSError as e:
            print("risk-tags: cannot write %s: %s" % (out_path, e), file=sys.stderr)
            result = "error"
    print(line)
    if result == "error":
        print("risk-tags: error — %s (fail closed: treat as review)" % (error or "see record"), file=sys.stderr)
    elif result == "clean":
        print("risk-tags: clean — no risk tag fired", file=sys.stderr)
    else:
        names = record["escalate_tags"] + record["review_tags"]
        print("risk-tags: %s — %s" % (result, ", ".join(names)), file=sys.stderr)
    sys.exit(EXIT[result])


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotePath=false", "-C", worktree] + list(args),
        capture_output=True, text=True, errors="replace")


def compile_all(patterns, where):
    if not isinstance(patterns, list) or not all(isinstance(p, str) and p for p in patterns):
        raise ValueError("%s must be a list of non-empty strings" % where)
    out = []
    for p in patterns:
        try:
            out.append((p, re.compile(p, re.IGNORECASE)))
        except re.error as e:
            raise ValueError("%s: bad pattern %r (%s)" % (where, p, e))
    return out


def check_tag(tag, where):
    if not isinstance(tag, dict):
        raise ValueError("%s is not an object" % where)
    tid = tag.get("id")
    if not isinstance(tid, str) or not re.match(r"^[a-z0-9][a-z0-9-]*$", tid):
        raise ValueError("%s has no valid id" % where)
    if tag.get("class") not in ("review", "escalate", None):
        raise ValueError("%s (%s): class must be review or escalate" % (where, tid))
    for key in ("paths", "lines"):
        if key in tag:
            compile_all(tag[key], "%s (%s).%s" % (where, tid, key))
    if "line_scope" in tag and not isinstance(tag["line_scope"], str):
        raise ValueError("%s (%s).line_scope must be a string" % (where, tid))
    return tid


# ── Config ────────────────────────────────────────────────────────────────────
try:
    with open(config_path) as fh:
        cfg = json.load(fh)
    if not isinstance(cfg, dict) or not isinstance(cfg.get("tags"), list) or not cfg["tags"]:
        raise ValueError("no tags list")
    tags = []
    for i, t in enumerate(cfg["tags"]):
        check_tag(t, "tags[%d]" % i)
        if t.get("class") is None:
            raise ValueError("tags[%d] (%s): class is required" % (i, t["id"]))
        tags.append({
            "id": t["id"], "class": t["class"], "description": t.get("description", ""),
            "paths": list(t.get("paths", [])), "lines": list(t.get("lines", [])),
            "line_scope": t.get("line_scope"),
        })
    ignore = compile_all(cfg.get("ignore_paths", []), "ignore_paths")
except (OSError, ValueError) as e:
    finish("error", "config %s unusable: %s" % (config_path, e))

# ── Refs ──────────────────────────────────────────────────────────────────────
shas = []
for ref in (base_ref, head_ref):
    r = git("rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if r.returncode != 0 or not r.stdout.strip():
        finish("error", "cannot resolve %r in %s" % (ref, worktree))
    shas.append(r.stdout.strip())
record["base"], record["head"] = shas

# ── Project block (additive only) ─────────────────────────────────────────────
if project_context:
    label = project_context
    try:
        with open(project_context) as fh:
            text = fh.read()
    except OSError as e:
        finish("error", "cannot read project file %s: %s" % (label, e))
else:
    label = "%s:project-context.md" % record["base"]
    r = git("show", label)
    text = r.stdout if r.returncode == 0 else ""
m = re.search(r"^```json[ \t]+risk_tags[ \t]*\n(.*?)^```", text, re.S | re.M)
if m:
    record["project_source"] = label
    try:
        proj = json.loads(m.group(1))
        if not isinstance(proj, dict) or not isinstance(proj.get("tags"), list):
            raise ValueError("block must be an object with a tags list")
        if set(proj) - {"tags", "about"}:
            raise ValueError("block may only carry tags (got %s); a project cannot set ignore_paths"
                             % ", ".join(sorted(set(proj) - {"tags", "about"})))
        by_id = {t["id"]: t for t in tags}
        for i, pt in enumerate(proj["tags"]):
            tid = check_tag(pt, "project tags[%d]" % i)
            if tid in by_id:
                cur = by_id[tid]
                if "line_scope" in pt:
                    raise ValueError("project tags[%d] (%s): cannot set line_scope on a default tag" % (i, tid))
                cur["paths"] += pt.get("paths", [])
                cur["lines"] += pt.get("lines", [])
                if pt.get("class") == "escalate":
                    cur["class"] = "escalate"
            else:
                if pt.get("class") is None:
                    raise ValueError("project tags[%d] (%s): class is required on a new tag" % (i, tid))
                if not pt.get("paths") and not pt.get("lines"):
                    raise ValueError("project tags[%d] (%s): a new tag needs paths or lines" % (i, tid))
                nt = {"id": tid, "class": pt["class"], "description": pt.get("description", ""),
                      "paths": list(pt.get("paths", [])), "lines": list(pt.get("lines", [])),
                      "line_scope": pt.get("line_scope")}
                tags.append(nt)
                by_id[tid] = nt
    except ValueError as e:
        finish("error", "project risk_tags block in %s unusable: %s" % (label, e))

for t in tags:
    t["_paths"] = compile_all(t["paths"], t["id"] + ".paths")
    t["_lines"] = compile_all(t["lines"], t["id"] + ".lines")
    t["_scope"] = re.compile(t["line_scope"], re.IGNORECASE) if t.get("line_scope") else None
    t["_hits"] = []
    t["_count"] = 0

# ── Changed paths (both sides of a rename) ────────────────────────────────────
r = git("diff", "--name-status", "-M", "--no-ext-diff", "%s...%s" % tuple(shas))
if r.returncode != 0:
    finish("error", "git diff --name-status failed: %s" % r.stderr.strip())
paths = []
for row in r.stdout.splitlines():
    parts = row.split("\t")
    for p in parts[1:]:
        if p and p not in paths:
            paths.append(p)
record["files_changed"] = len(paths)


def ignored(path):
    return any(rx.search(path) for _, rx in ignore)


def hit(tag, entry):
    tag["_count"] += 1
    if len(tag["_hits"]) < MAX_HITS_PER_TAG:
        tag["_hits"].append(entry)


for p in paths:
    if ignored(p):
        record["files_ignored"].append(p)
        continue
    record["files_scanned"] += 1
    for t in tags:
        for src, rx in t["_paths"]:
            if rx.search(p):
                hit(t, {"kind": "path", "file": p, "pattern": src})
                break

# ── Changed lines ─────────────────────────────────────────────────────────────
# Parse a -U0 diff with hunk counters, so a removed SQL comment ("-- x" shows as
# "--- x") is read as a changed line, never as a file header.
r = git("diff", "-U0", "-M", "--no-color", "--no-ext-diff", "%s...%s" % tuple(shas))
if r.returncode != 0:
    finish("error", "git diff failed: %s" % r.stderr.strip())

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def strip_prefix(name):
    name = name.rstrip("\t")
    if name.startswith('"') and name.endswith('"'):
        name = name[1:-1]
    if name == "/dev/null":
        return None
    return name[2:] if name[:2] in ("a/", "b/") else name


old_name = new_name = None
cur = None
rem_old = rem_new = 0
old_ln = new_ln = 0
for raw in r.stdout.split("\n"):
    if rem_old > 0 or rem_new > 0:
        if raw.startswith("-") and rem_old > 0:
            side, ln = "-", old_ln
            old_ln += 1
            rem_old -= 1
        elif raw.startswith("+") and rem_new > 0:
            side, ln = "+", new_ln
            new_ln += 1
            rem_new -= 1
        elif raw.startswith("\\"):
            continue
        else:
            rem_old = rem_new = 0
            side = None
        if side is not None:
            if cur is None or ignored(cur):
                continue
            body = raw[1:]
            for t in tags:
                if t["_scope"] is not None and not t["_scope"].search(cur):
                    continue
                for src, rx in t["_lines"]:
                    if rx.search(body):
                        hit(t, {"kind": "line", "file": cur, "side": side, "line": ln, "pattern": src})
                        break
            continue
    if raw.startswith("diff --git "):
        old_name = new_name = cur = None
    elif raw.startswith("--- "):
        old_name = strip_prefix(raw[4:])
        cur = new_name or old_name
    elif raw.startswith("+++ "):
        new_name = strip_prefix(raw[4:])
        cur = new_name or old_name
    else:
        mh = HUNK.match(raw)
        if mh:
            old_ln = int(mh.group(1))
            rem_old = int(mh.group(2)) if mh.group(2) is not None else 1
            new_ln = int(mh.group(3))
            rem_new = int(mh.group(4)) if mh.group(4) is not None else 1

# ── Verdict ───────────────────────────────────────────────────────────────────
for t in tags:
    if t["_count"]:
        record["fired"].append({
            "id": t["id"], "class": t["class"], "description": t["description"],
            "hit_count": t["_count"], "hits": t["_hits"],
        })
        record["escalate_tags" if t["class"] == "escalate" else "review_tags"].append(t["id"])

if record["escalate_tags"]:
    finish("escalate")
if record["review_tags"]:
    finish("review")
finish("clean")
PY
