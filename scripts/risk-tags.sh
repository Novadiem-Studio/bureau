#!/bin/sh
# risk-tags.sh — decide, mechanically, whether one build unit's diff needs a cold review.
#
# workflows/bureau-lite.md runs the per-unit cold build-diff Challenger only on units whose
# diff touches an enumerated risk surface (OAuth/auth, tokens and secrets, network egress,
# tool allowlists, redaction, migrations, irreversible sends, concurrency). Which units those
# are is decided here, by matching the diff's changed paths and changed lines against a fixed
# pattern list, never by the Conductor's reading of the diff. The Conductor may ADD a review
# this script did not ask for; it may not skip one this script did ask for, and
# scripts/risk-coverage.sh checks afterwards that every commit was scanned and every flagged
# record was reviewed.
#
# Usage:
#   scripts/risk-tags.sh --worktree <abs path> --base <ref> [--head <ref>] \
#     [--policy-ref <ref>] [--config <risk-tags.json>] [--project-context <path>] \
#     [--out <record.json>]
#
#   --worktree         the git worktree the unit was built in. Must be clean (no staged,
#                      unstaged or untracked changes): uncommitted code is never scanned.
#   --base             the commit the unit started from. The range is base..head (two-dot),
#                      base must be an ancestor of head, and the range must hold at least one
#                      commit; anything else is an error, never "clean".
#   --head             default HEAD.
#   --policy-ref       the commit whose project-context.md supplies the project's
#                      ```json risk_tags``` block. Pass the run's start commit
#                      (state.json#git.base_sha) so nothing the run commits can change its
#                      own triggers. Default: --base (weaker; recorded in the output).
#   --config           default <framework>/config/risk-tags.json.
#   --project-context  read the project block from this file instead of git (for a project
#                      file kept outside the target repo).
#   --out              also write the record to this file.
#
# A project block may only ADD: new tags, extra patterns on an existing tag, or
# `"class": "escalate"` on an existing tag. Setting ignore_paths, lowering a class,
# narrowing a default tag with line_scope, or carrying two risk_tags blocks is an error.
#
# Exit codes (stdout carries one JSON line either way; --out gets the same record):
#   0  clean    — no tag fired. The unit ships on the coder's tests + CodeRabbit.
#   1  review   — one or more `review` tags fired and no `escalate` tag did.
#                 Run the cold build-diff Challenger on this unit.
#   3  escalate — an `escalate` tag fired (money, destructive migration). This is no longer
#                 a bureau-lite unit: stop and checkpoint.
#   2  error    — bad arguments, a dirty worktree, an unresolvable, non-ancestor or empty
#                 range, an invalid config or project block, or any internal failure.
#                 Fail closed: the caller treats this as `review`.
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
POLICY_REF=""
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
    --policy-ref)      POLICY_REF="$2";      shift 2 ;;
    --config)          CONFIG="$2";          shift 2 ;;
    --project-context) PROJECT_CONTEXT="$2"; shift 2 ;;
    --out)             OUT="$2";             shift 2 ;;
    *) echo "risk-tags: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKTREE" ] || [ -z "$BASE" ]; then
  echo "usage: risk-tags.sh --worktree <path> --base <ref> [--head <ref>] [--policy-ref <ref>] [--config <file>] [--project-context <file>] [--out <file>]" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "risk-tags: python3 not found (fail closed: treat as review)" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "risk-tags: git not found (fail closed: treat as review)" >&2; exit 2; }

python3 - "$WORKTREE" "$BASE" "$HEAD_REF" "$POLICY_REF" "$CONFIG" "$PROJECT_CONTEXT" "$OUT" <<'PY'
import datetime
import hashlib
import json
import re
import subprocess
import sys

worktree, base_ref, head_ref, policy_ref, config_path, project_context, out_path = sys.argv[1:8]
EXIT = {"clean": 0, "review": 1, "error": 2, "escalate": 3}
MAX_HITS_PER_TAG = 20


class Fail(Exception):
    pass


record = {
    "schema": 2,
    "result": None,
    "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "base": base_ref,
    "head": head_ref,
    "commits": 0,
    "policy_ref": policy_ref or None,
    "config": config_path,
    "config_sha256": None,
    "project_source": None,
    "paths_changed": 0,
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
    if out_path:
        try:
            with open(out_path, "w") as fh:
                fh.write(json.dumps(record, indent=2, sort_keys=True) + "\n")
        except OSError as e:
            result = "error"
            record["result"] = "error"
            record["error"] = "cannot write %s: %s" % (out_path, e)
    print(json.dumps(record, sort_keys=True))
    if result == "error":
        print("risk-tags: error — %s (fail closed: treat as review)" % record.get("error", "see record"), file=sys.stderr)
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
        raise Fail("%s must be a list of non-empty strings" % where)
    out = []
    for p in patterns:
        try:
            out.append((p, re.compile(p, re.IGNORECASE)))
        except re.error as e:
            raise Fail("%s: bad pattern %r (%s)" % (where, p, e))
    return out


def check_tag(tag, where):
    if not isinstance(tag, dict):
        raise Fail("%s is not an object" % where)
    tid = tag.get("id")
    if not isinstance(tid, str) or not re.match(r"^[a-z0-9][a-z0-9-]*$", tid):
        raise Fail("%s has no valid id" % where)
    if tag.get("class") not in ("review", "escalate", None):
        raise Fail("%s (%s): class must be review or escalate" % (where, tid))
    for key in ("paths", "lines"):
        if key in tag:
            compile_all(tag[key], "%s (%s).%s" % (where, tid, key))
    if "line_scope" in tag:
        if not isinstance(tag["line_scope"], str):
            raise Fail("%s (%s).line_scope must be a string" % (where, tid))
        compile_all([tag["line_scope"]], "%s (%s).line_scope" % (where, tid))
    return tid


def resolve(ref):
    r = git("rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if r.returncode != 0 or not r.stdout.strip():
        raise Fail("cannot resolve %r in %s" % (ref, worktree))
    return r.stdout.strip()


def unquote(name):
    """Undo git's C-style quoting of a path ("a/we\\"ird" -> a/we"ird)."""
    if len(name) >= 2 and name[0] == '"' and name[-1] == '"':
        raw = name[1:-1].encode("latin-1", "backslashreplace")
        return raw.decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
    return name


def main():
    # ── Config ────────────────────────────────────────────────────────────────
    try:
        with open(config_path, "rb") as fh:
            raw = fh.read()
        record["config_sha256"] = hashlib.sha256(raw).hexdigest()
        cfg = json.loads(raw.decode("utf-8"))
    except (OSError, ValueError) as e:
        raise Fail("config %s unusable: %s" % (config_path, e))
    if not isinstance(cfg, dict) or not isinstance(cfg.get("tags"), list) or not cfg["tags"]:
        raise Fail("config %s has no tags list" % config_path)
    tags = []
    for i, t in enumerate(cfg["tags"]):
        check_tag(t, "tags[%d]" % i)
        if t.get("class") is None:
            raise Fail("tags[%d] (%s): class is required" % (i, t["id"]))
        tags.append({
            "id": t["id"], "class": t["class"], "description": t.get("description", ""),
            "paths": list(t.get("paths", [])), "lines": list(t.get("lines", [])),
            "line_scope": t.get("line_scope"),
        })
    ignore = compile_all(cfg.get("ignore_paths", []), "ignore_paths")
    ignore_except = compile_all(cfg.get("ignore_except", []), "ignore_except")

    # ── Worktree and range ────────────────────────────────────────────────────
    st = git("status", "--porcelain")
    if st.returncode != 0:
        raise Fail("git status failed in %s: %s" % (worktree, st.stderr.strip()))
    if st.stdout.strip():
        raise Fail("worktree has uncommitted or untracked changes; commit them first so they are scanned")
    base, head = resolve(base_ref), resolve(head_ref)
    record["base"], record["head"] = base, head
    if git("merge-base", "--is-ancestor", base, head).returncode != 0:
        raise Fail("base %s is not an ancestor of head %s (history rewritten, or wrong base)" % (base[:12], head[:12]))
    count = git("rev-list", "--count", "%s..%s" % (base, head))
    record["commits"] = int(count.stdout.strip() or 0) if count.returncode == 0 else 0
    if record["commits"] < 1:
        raise Fail("empty range %s..%s: nothing to scan" % (base[:12], head[:12]))

    # ── Project block (additive only), read from the policy ref ───────────────
    pref = resolve(policy_ref) if policy_ref else base
    record["policy_ref"] = pref
    if project_context:
        label = project_context
        try:
            with open(project_context) as fh:
                text = fh.read()
        except OSError as e:
            raise Fail("cannot read project file %s: %s" % (label, e))
    else:
        label = "%s:project-context.md" % pref
        listed = git("ls-tree", pref, "--", "project-context.md")
        if listed.returncode != 0:
            raise Fail("cannot list project policy at %s: %s" % (pref[:12], listed.stderr.strip()))
        if listed.stdout.strip():
            r = git("show", label)
            if r.returncode != 0:
                raise Fail("cannot read %s: %s" % (label, r.stderr.strip()))
            text = r.stdout
        else:
            text = ""
    text = text.replace("\r\n", "\n")
    # Lenient on indentation and case, strict on count: any fence line that names
    # risk_tags must parse as exactly one block, or the scan fails closed.
    openers = re.findall(r"^[ \t]*```[ \t]*json[ \t]+risk_tags\b", text, re.M | re.I)
    blocks = re.findall(r"^[ \t]*```[ \t]*json[ \t]+risk_tags[ \t]*\n(.*?)^[ \t]*```", text, re.S | re.M | re.I)
    if len(openers) > 1:
        raise Fail("%s carries %d risk_tags blocks; keep one" % (label, len(openers)))
    if len(openers) != len(blocks):
        raise Fail("%s has a risk_tags fence that does not parse as a block" % label)
    if blocks:
        record["project_source"] = label
        try:
            proj = json.loads(blocks[0])
        except ValueError as e:
            raise Fail("project risk_tags block in %s is not JSON: %s" % (label, e))
        if not isinstance(proj, dict) or not isinstance(proj.get("tags"), list):
            raise Fail("project risk_tags block must be an object with a tags list")
        extra = set(proj) - {"tags", "about"}
        if extra:
            raise Fail("project risk_tags block may only carry tags (got %s); a project cannot set ignore_paths"
                       % ", ".join(sorted(extra)))
        by_id = {t["id"]: t for t in tags}
        for i, pt in enumerate(proj["tags"]):
            tid = check_tag(pt, "project tags[%d]" % i)
            if tid in by_id:
                cur = by_id[tid]
                if "line_scope" in pt:
                    raise Fail("project tags[%d] (%s): cannot set line_scope on a default tag" % (i, tid))
                if pt.get("class") == "review" and cur["class"] == "escalate":
                    raise Fail("project tags[%d] (%s): cannot lower an escalate tag to review" % (i, tid))
                cur["paths"] += pt.get("paths", [])
                cur["lines"] += pt.get("lines", [])
                if pt.get("class") == "escalate":
                    cur["class"] = "escalate"
            else:
                if pt.get("class") is None:
                    raise Fail("project tags[%d] (%s): class is required on a new tag" % (i, tid))
                if not pt.get("paths") and not pt.get("lines"):
                    raise Fail("project tags[%d] (%s): a new tag needs paths or lines" % (i, tid))
                nt = {"id": tid, "class": pt["class"], "description": pt.get("description", ""),
                      "paths": list(pt.get("paths", [])), "lines": list(pt.get("lines", [])),
                      "line_scope": pt.get("line_scope")}
                tags.append(nt)
                by_id[tid] = nt

    for t in tags:
        t["_paths"] = compile_all(t["paths"], t["id"] + ".paths")
        t["_lines"] = compile_all(t["lines"], t["id"] + ".lines")
        t["_scope"] = re.compile(t["line_scope"], re.IGNORECASE) if t.get("line_scope") else None
        t["_hits"] = []
        t["_count"] = 0

    def ignored(path):
        if any(rx.search(path) for _, rx in ignore_except):
            return False
        return any(rx.search(path) for _, rx in ignore)

    def hit(tag, entry):
        tag["_count"] += 1
        if len(tag["_hits"]) < MAX_HITS_PER_TAG:
            tag["_hits"].append(entry)

    # ── Changed paths: -z, both sides of a rename ─────────────────────────────
    r = git("diff", "--name-status", "-z", "-M", "--no-ext-diff", base, head)
    if r.returncode != 0:
        raise Fail("git diff --name-status failed: %s" % r.stderr.strip())
    if r.stdout and not r.stdout.endswith("\0"):
        raise Fail("truncated git diff --name-status record")
    fields = r.stdout.split("\0")[:-1]
    paths = []
    i = 0
    while i < len(fields):
        status = fields[i]
        if not re.fullmatch(r"(?:[ACDMRTUXB]|[RCM][0-9]+)", status):
            raise Fail("invalid git diff --name-status status %r" % status)
        n = 2 if status[:1] in ("R", "C") else 1
        if len(fields) < i + 1 + n or not all(fields[i + 1:i + 1 + n]):
            raise Fail("truncated git diff --name-status paths")
        for p in fields[i + 1:i + 1 + n]:
            if p and p not in paths:
                paths.append(p)
        i += 1 + n
    record["paths_changed"] = len(paths)

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

    # ── Changed lines ─────────────────────────────────────────────────────────
    # Parse a -U0 diff with hunk counters, so a removed SQL comment ("-- x" shows as
    # "--- x") is read as a changed line, never as a file header. Fixed a/ b/ prefixes
    # and no textconv, whatever the user's git config says.
    r = git("diff", "-U0", "-M", "--no-color", "--no-ext-diff", "--no-textconv",
            "--src-prefix=a/", "--dst-prefix=b/", base, head)
    if r.returncode != 0:
        raise Fail("git diff failed: %s" % r.stderr.strip())

    hunk_rx = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")

    def header_name(raw):
        name = unquote(raw.rstrip("\t"))
        if name == "/dev/null":
            return None
        return name[2:] if name[:2] in ("a/", "b/") else name

    old_name = new_name = cur = None
    rem_old = rem_new = 0
    old_ln = new_ln = 0
    for line in r.stdout.split("\n"):
        if rem_old > 0 or rem_new > 0:
            side = None
            if line.startswith("-") and rem_old > 0:
                side, ln = "-", old_ln
                old_ln += 1
                rem_old -= 1
            elif line.startswith("+") and rem_new > 0:
                side, ln = "+", new_ln
                new_ln += 1
                rem_new -= 1
            elif line.startswith("\\"):
                continue
            else:
                rem_old = rem_new = 0
            if side is not None:
                names = [n for n in (old_name, new_name) if n]
                if not names or all(ignored(n) for n in names):
                    continue
                body = line[1:]
                for t in tags:
                    if t["_scope"] is not None and not any(t["_scope"].search(n) for n in names):
                        continue
                    for src, rx in t["_lines"]:
                        if rx.search(body):
                            hit(t, {"kind": "line", "file": old_name if side == "-" else new_name,
                                    "side": side, "line": ln, "pattern": src})
                            break
                continue
        if line.startswith("diff --git "):
            old_name = new_name = cur = None
        elif line.startswith("--- "):
            old_name = header_name(line[4:])
            cur = new_name or old_name
        elif line.startswith("+++ "):
            new_name = header_name(line[4:])
            cur = new_name or old_name
        else:
            mh = hunk_rx.match(line)
            if mh:
                old_ln = int(mh.group(1))
                rem_old = int(mh.group(2)) if mh.group(2) is not None else 1
                new_ln = int(mh.group(3))
                rem_new = int(mh.group(4)) if mh.group(4) is not None else 1

    # ── Verdict ───────────────────────────────────────────────────────────────
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


try:
    main()
except Fail as e:
    finish("error", str(e))
except SystemExit:
    raise
except Exception as e:  # any bug fails closed, with a record
    finish("error", "internal error: %s: %s" % (type(e).__name__, e))
PY
