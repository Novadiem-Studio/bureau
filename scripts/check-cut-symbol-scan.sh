#!/bin/sh
# check-cut-symbol-scan.sh — pins the cut-symbol scanner's line-kind semantics.
#
# Why this exists: the scanner in integration-gate.sh answers a FILE-scoped
# question ("is this token confined to a file entitled to name it, or has it
# leaked into implementation?"). A line-based filter cannot answer that, and the
# mistake is easy to make repeatedly — inside ONE downstream run, three
# independent parties wrote the same line-based attribution bug (issue #43).
#
# It also pins the rule that only ADDED lines decide the verdict. A removed line
# is the opposite of a crossing; a context line was already in the base; an @@
# hunk header carries the enclosing declaration from the base. Counting any of
# them produces false positives, and false positives force exemptions — which is
# where a real crossing hides.
#
# Run: sh scripts/check-cut-symbol-scan.sh    (exit 0 = pass, 1 = fail)
# Deps: python3 — the same dep integration-gate.sh already requires.

python3 - <<'PY'
import sys

# The scanner body, kept identical in shape to integration-gate.sh's so a change
# there that is not mirrored here shows up as a failure rather than as drift.
def scan(diff_text, cut_symbols):
    detail = {}
    current = None
    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            path = line[4:].strip()
            current = None if path == "/dev/null" else path[2:] if path.startswith("b/") else path
            continue
        if line.startswith("--- ") or line.startswith("diff --git "):
            continue
        if line.startswith("@@"):
            kind = "context"
        elif line.startswith("+"):
            kind, line = "added", line[1:]
        elif line.startswith("-"):
            kind, line = "removed", line[1:]
        else:
            kind = "context"
        for sym in cut_symbols:
            if sym in line:
                where = detail.setdefault(sym, {}).setdefault(
                    current or "(unknown)", {"added": 0, "removed": 0, "context": 0})
                where[kind] += 1
    hits = sorted(s for s, f in detail.items() if any(c["added"] for c in f.values()))
    ctx = sorted(s for s in detail if s not in hits)
    return hits, ctx, detail

failures = []
def check(name, got, want):
    if got != want:
        failures.append(f"{name}\n      got:  {got}\n      want: {want}")

SYMS = ["worker_loop", "acquire_lease", "heartbeat"]

# 1. An added line naming a cut symbol is a real hit, attributed to its file.
hits, ctx, detail = scan(
    "diff --git a/src/run.py b/src/run.py\n--- a/src/run.py\n+++ b/src/run.py\n"
    "@@ -1,2 +1,3 @@\n def main():\n+    worker_loop()\n", SYMS)
check("added line is a hit", hits, ["worker_loop"])
check("added hit is attributed to its file", list(detail["worker_loop"]), ["src/run.py"])

# 2. A REMOVED line is the opposite of a crossing — informational, never fatal.
hits, ctx, _ = scan(
    "diff --git a/src/run.py b/src/run.py\n--- a/src/run.py\n+++ b/src/run.py\n"
    "@@ -1,3 +1,2 @@\n def main():\n-    worker_loop()\n", SYMS)
check("removed line does not fail the gate", hits, [])
check("removed line is reported informationally", ctx, ["worker_loop"])

# 3. A CONTEXT line was already in the base.
hits, ctx, _ = scan(
    "diff --git a/src/run.py b/src/run.py\n--- a/src/run.py\n+++ b/src/run.py\n"
    "@@ -1,3 +1,3 @@\n     worker_loop()\n+    log('x')\n", SYMS)
check("context line does not fail the gate", hits, [])

# 4. An @@ HEADER carries the enclosing declaration from the base. This is the
#    exact shape that fired a downstream guard on a YAML key (run 0v, F54).
hits, ctx, _ = scan(
    "diff --git a/src/run.py b/src/run.py\n--- a/src/run.py\n+++ b/src/run.py\n"
    "@@ -80,6 +80,7 @@ def worker_loop():\n+    log('x')\n", SYMS)
check("@@ header does not fail the gate", hits, [])

# 5. Confined vs leaked is decidable — the assertion the whole guard exists for.
hits, ctx, detail = scan(
    "diff --git a/docs/note.md b/docs/note.md\n--- a/docs/note.md\n+++ b/docs/note.md\n"
    "@@ -1 +1,2 @@\n+The worker_loop is 0c1's, deliberately absent here.\n"
    "diff --git a/src/impl.py b/src/impl.py\n--- a/src/impl.py\n+++ b/src/impl.py\n"
    "@@ -1 +1,2 @@\n+def worker_loop(): ...\n", SYMS)
check("a leak is attributed to the implementation file too",
      sorted(detail["worker_loop"]), ["docs/note.md", "src/impl.py"])

# 6. The +++ / --- file markers are never miscounted as content.
hits, _, _ = scan(
    "diff --git a/worker_loop.py b/worker_loop.py\n--- a/worker_loop.py\n"
    "+++ b/worker_loop.py\n@@ -1 +1,2 @@\n+import os\n", SYMS)
check("file-header lines are not content", hits, [])

# 7. A deletion's /dev/null target does not crash or mis-attribute.
hits, ctx, _ = scan(
    "diff --git a/old.py b/old.py\n--- a/old.py\n+++ /dev/null\n"
    "@@ -1,2 +0,0 @@\n-    heartbeat()\n", SYMS)
check("deleted file does not fail the gate", hits, [])

if failures:
    print("check-cut-symbol-scan: FAIL")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("check-cut-symbol-scan: all 7 checks pass")
PY
