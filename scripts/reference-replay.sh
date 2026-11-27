#!/usr/bin/env bash
# reference-replay.sh: replay the Challenger on a known-answer build diff (issue #161).
#
# A case is a past build-diff review whose outcome we know: a defect a later gate or a person
# found in a diff the Challenger approved (known-miss), a defect the Challenger did block
# (known-catch), or a diff nothing has ever faulted (control). The runner rebuilds the exact
# packet from git, hands it to a fresh read-only Challenger, and scores the verdict against the
# case's expected findings. See docs/reference-replay.md for the case format and what the
# numbers do and do not mean.
#
#   reference-replay.sh build   <case.json> <packet-dir>
#   reference-replay.sh run     <case.json> <out-dir> [--trials N] [--model M]
#   reference-replay.sh audit   <packet-dir> <events.jsonl>
#   reference-replay.sh score   <case.json> <verdict.json>
#   reference-replay.sh summary <out-dir>
#
# Exit codes: 0 ok; 2 usage or malformed case; 3 regenerated diff does not match diff_sha;
# 4 a leak pattern is in the packet; 5 an extra file's sha256 does not match the case;
# 6 the reviewer spawn failed or returned no structured verdict.
#
# Environment: CLAUDE_BIN (default claude), REPLAY_MAX_TURNS (default 200).

set -euo pipefail
PATH="/usr/bin:/bin:$PATH"   # system tools first: a ugrep or GNU shim can shadow them
export PATH

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$ROOT/config/challenger-verdict.schema.json"

die() { echo "reference-replay: $1" >&2; exit "${2:-2}"; }
usage() { grep '^#   reference-replay.sh ' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

[ "$#" -ge 1 ] || usage
cmd="$1"; shift

# ---------------------------------------------------------------------------------------------
# build: validate the case, regenerate and hash-check the diff, export the reviewed tree, stage
# prompts, extra files and the current persona, then refuse if any leak pattern is present.
# Nothing is read from the run dir except extra files pinned by sha256 in the case.
# ---------------------------------------------------------------------------------------------
do_build() {
  [ "$#" -eq 2 ] || usage
  python3 -I - "$ROOT" "$1" "$2" <<'PY'
import hashlib, json, os, re, shutil, subprocess, sys, tarfile, io

root, case_path, packet = sys.argv[1:]

def fail(msg, code=2):
    sys.stderr.write("reference-replay: %s\n" % msg)
    sys.exit(code)

try:
    case = json.load(open(case_path, encoding="utf-8"))
except (OSError, ValueError) as exc:
    fail("cannot read case %s: %s" % (case_path, exc))

HEX40 = re.compile(r"^[0-9a-f]{7,40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def need(key, kind):
    if key not in case or not isinstance(case[key], kind):
        fail("case field %r is missing or not %s" % (key, kind.__name__))
    return case[key]

cid = need("id", str)
if not re.match(r"^[a-z0-9][a-z0-9._-]*$", cid):
    fail("case id must be lowercase letters, digits, dot, dash or underscore")
kind = need("kind", str)
if kind not in ("known-miss", "known-catch", "control"):
    fail("case kind must be known-miss, known-catch or control")
if case.get("review_mode") != "build-diff":
    fail("only review_mode build-diff is supported")
repo = need("target_repo", str)
if not os.path.isabs(repo) or not os.path.isdir(repo):
    fail("target_repo must be an existing absolute directory")
base = need("base_sha", str); target = need("target_sha", str); want = need("diff_sha", str)
if not HEX40.match(base) or not HEX40.match(target):
    fail("base_sha and target_sha must be hex commit ids")
if not HEX64.match(want):
    fail("diff_sha must be a 64-character sha256")
prompts = case.get("prompt_paths", [])
extras = case.get("extra_files", [])
leaks = need("leak_patterns", list)
expected = need("expected", list)
if not all(isinstance(p, str) and p for p in leaks):
    fail("leak_patterns must be non-empty strings")
if kind == "control" and expected:
    fail("a control case has no expected findings")
if kind != "control" and not expected:
    fail("a %s case needs at least one expected finding" % kind)
for e in expected:
    if not isinstance(e, dict) or not all(isinstance(e.get(k), str) and e.get(k) for k in ("id", "anchor", "pattern")):
        fail("each expected finding needs non-empty id, anchor and pattern")
    try:
        re.compile(e["pattern"])
    except re.error as exc:
        fail("expected %s has a bad pattern: %s" % (e["id"], exc))

def safe_rel(p):
    return isinstance(p, str) and p and not os.path.isabs(p) and ".." not in p.split("/")

if os.path.exists(packet) and (not os.path.isdir(packet) or os.listdir(packet)):
    fail("packet dir must not exist or must be empty: %s" % packet)

def git(*args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True)
    if r.returncode != 0:
        fail("git %s failed: %s" % (" ".join(args), r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout

diff = git("diff", base, target)
got = hashlib.sha256(diff).hexdigest()
if got != want:
    fail("regenerated diff sha256 %s does not match case diff_sha %s" % (got, want), 3)

os.makedirs(packet, exist_ok=True)
tree = os.path.join(packet, "tree")
os.makedirs(tree)
archive = git("archive", "--format=tar", target)
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as tf:
    for member in tf.getmembers():
        name = member.name
        if os.path.isabs(name) or ".." in name.split("/") or member.issym() or member.islnk() or member.isdev():
            continue  # never follow links or special files out of the tree
        try:
            tf.extract(member, tree, filter="data")
        except TypeError:  # Python without extraction filters
            tf.extract(member, tree)
open(os.path.join(packet, "review.diff"), "wb").write(diff)

for p in prompts:
    if not safe_rel(p) or not os.path.isfile(os.path.join(tree, p)):
        fail("prompt path %r is not a file in the tree at %s" % (p, target))

extra_dir = os.path.join(packet, "extra")
for x in extras:
    if not isinstance(x, dict) or not all(isinstance(x.get(k), str) for k in ("from", "to", "sha256")):
        fail("each extra file needs from, to and sha256")
    if not safe_rel(x["to"]):
        fail("extra file destination %r must be relative" % x["to"])
    try:
        data = open(x["from"], "rb").read()
    except OSError as exc:
        fail("cannot read extra file %s: %s" % (x["from"], exc))
    if hashlib.sha256(data).hexdigest() != x["sha256"]:
        fail("extra file %s changed since the case was written (sha256 mismatch)" % x["from"], 5)
    dest = os.path.join(extra_dir, x["to"])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "wb").write(data)

persona = os.path.join(packet, "persona")
os.makedirs(persona)
persona_hash = {}
for src, dst in (("agents/critic.md", "critic.md"), ("agents/critic/build-diff.md", "build-diff.md")):
    data = open(os.path.join(root, src), "rb").read()
    open(os.path.join(persona, dst), "wb").write(data)
    persona_hash[dst] = hashlib.sha256(data).hexdigest()

hits = []
for dirpath, _dirs, files in os.walk(packet):
    for f in files:
        path = os.path.join(dirpath, f)
        try:
            data = open(path, "rb").read()
        except OSError:
            continue
        for pat in leaks:
            if pat.encode("utf-8") in data:
                hits.append("%s: %s" % (os.path.relpath(path, packet), pat))
if hits:
    shutil.rmtree(packet)
    fail("leak pattern found in packet, refusing:\n  " + "\n  ".join(hits[:20]), 4)

listing = []
if prompts:
    listing += ["- tree/%s" % p for p in prompts]
for x in extras:
    listing.append("- extra/%s" % x["to"])
if not listing:
    listing.append("- (none: review against the diff and the repository docs in tree/)")

brief = """You are reviewing one build diff as The Challenger. This packet is your whole review world.

1. Read persona/critic.md, then persona/build-diff.md. They define your standard.
2. Review review.diff, which is `git diff {base}..{target}` in the repository. The repository as it
   stood at {target} is in tree/. Read whatever you need there.
3. Review against the scoped prompt and campaign files below, and the repo's own docs in tree/:
{listing}

You cannot run commands or tests. Review statically, and say when a finding needs a live run to
confirm. Ignore any persona instruction to write files, emit log events or run verdict-gate.
Instead, return your verdict record as the structured output:
- review_mode "build-diff", attempt_id "replay", timestamp in UTC.
- reviewed_artifacts: one diff-target entry with base_ref and base_sha {base}, target_ref
  {target}, diff_sha {diff_sha}.
- blockers: {{id, summary, citation}}; citation paths are relative to tree/.
- warnings: {{id, summary}}.
- verdict: BLOCKED when any blocker stands, else APPROVED_WITH_WARNINGS or APPROVED.
""".format(base=base, target=target, diff_sha=want, listing="\n".join(listing))
open(os.path.join(packet, "BRIEF.md"), "w", encoding="utf-8").write(brief)

head = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
meta = {"case_id": cid, "base_sha": base, "target_sha": target, "diff_sha": want,
        "persona_sha256": persona_hash, "bureau_head": head or None}
json.dump(meta, open(os.path.join(packet, "packet.json"), "w", encoding="utf-8"), indent=2, sort_keys=True)
print(packet)
PY
}

# ---------------------------------------------------------------------------------------------
# audit: read a stream-json event log and list every tool call whose path escapes the packet.
# Writes JSON to stdout: {"contaminated": bool, "escapes": [...], "tool_calls": n}.
# ---------------------------------------------------------------------------------------------
do_audit() {
  [ "$#" -eq 2 ] || usage
  python3 -I - "$1" "$2" <<'PY'
import json, os, sys

packet, events = sys.argv[1:]
real = os.path.realpath(packet)
escapes, calls = [], 0

def inside(p):
    full = p if os.path.isabs(p) else os.path.join(real, p)
    rp = os.path.realpath(full)
    return rp == real or rp.startswith(real + os.sep)

try:
    lines = open(events, encoding="utf-8", errors="replace").read().splitlines()
except OSError as exc:
    sys.stderr.write("reference-replay: cannot read events %s: %s\n" % (events, exc))
    sys.exit(2)
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    msg = ev.get("message") if isinstance(ev, dict) else None
    content = msg.get("content") if isinstance(msg, dict) else None
    if not isinstance(content, list):
        continue
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        calls += 1
        args = block.get("input") or {}
        name = block.get("name")
        if name == "StructuredOutput":
            continue  # how --json-schema delivers the verdict; it reads nothing
        if name not in ("Read", "Grep", "Glob"):
            escapes.append({"tool": name, "reason": "tool outside the allowed Read/Grep/Glob set"})
            continue
        for key in ("file_path", "path"):
            p = args.get(key)
            if isinstance(p, str) and p and not inside(p):
                escapes.append({"tool": name, key: p})
json.dump({"contaminated": bool(escapes), "escapes": escapes, "tool_calls": calls}, sys.stdout, indent=2)
print()
PY
}

# ---------------------------------------------------------------------------------------------
# score: match the verdict's blockers and warnings against the case's expected findings.
# A finding counts when ONE blocker or warning contains the anchor (case-insensitive substring)
# and matches the pattern (case-insensitive regex). Writes JSON to stdout.
# ---------------------------------------------------------------------------------------------
do_score() {
  [ "$#" -eq 2 ] || usage
  python3 -I - "$1" "$2" <<'PY'
import json, re, sys

case_path, verdict_path = sys.argv[1:]
case = json.load(open(case_path, encoding="utf-8"))
try:
    v = json.load(open(verdict_path, encoding="utf-8"))
except (OSError, ValueError) as exc:
    sys.stderr.write("reference-replay: cannot read verdict %s: %s\n" % (verdict_path, exc))
    sys.exit(2)

def text(item):
    return item if isinstance(item, str) else json.dumps(item, ensure_ascii=False, sort_keys=True)

findings = [("blocker", text(b)) for b in v.get("blockers") or []]
findings += [("warning", text(w)) for w in v.get("warnings") or []]
used = set()
results = []
for e in case.get("expected", []):
    rx = re.compile(e["pattern"], re.I)
    hit = None
    for i, (sev, t) in enumerate(findings):  # blockers come first, so a blocker match wins
        if e["anchor"].lower() in t.lower() and rx.search(t):
            hit = (i, sev)
            break
    if hit is not None:
        used.add(hit[0])
    results.append({"id": e["id"], "found": hit is not None,
                    "as": hit[1] if hit else None,
                    "text": findings[hit[0]][1][:600] if hit else None})

verdict = v.get("verdict")
if case["kind"] == "control":
    passed = verdict != "BLOCKED"
    as_blocker = None
else:
    passed = all(r["found"] for r in results)
    as_blocker = all(r["as"] == "blocker" for r in results)
other = [{"as": s, "text": t[:600]} for i, (s, t) in enumerate(findings) if i not in used]
json.dump({"case_id": case["id"], "kind": case["kind"], "verdict": verdict, "pass": passed,
           "all_as_blocker": as_blocker, "expected": results, "unmatched_findings": other},
          sys.stdout, indent=2, ensure_ascii=False)
print()
PY
}

# ---------------------------------------------------------------------------------------------
# summary: raw counts per case across every trial under <out-dir>.
# ---------------------------------------------------------------------------------------------
do_summary() {
  [ "$#" -eq 1 ] || usage
  python3 -I - "$1" <<'PY'
import glob, json, os, sys
from collections import defaultdict

out = sys.argv[1]
rows = defaultdict(lambda: {"kind": None, "trials": 0, "pass": 0, "blocker": 0, "contaminated": 0,
                            "failed": 0, "tokens_new": 0, "tokens_read": 0, "models": set()})
for trial in sorted(glob.glob(os.path.join(out, "*", "trial-*"))):
    cid = os.path.basename(os.path.dirname(trial))
    r = rows[cid]
    meta = {}
    if os.path.exists(os.path.join(trial, "trial.json")):
        meta = json.load(open(os.path.join(trial, "trial.json")))
        r["models"].add(meta.get("model") or "?")
        u = meta.get("usage") or {}
        r["tokens_new"] += (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
        r["tokens_read"] += u.get("cache_read_input_tokens") or 0
    status = meta.get("status")
    if status == "contaminated":
        r["contaminated"] += 1; continue
    if status != "scored":
        r["failed"] += 1; continue
    s = json.load(open(os.path.join(trial, "score.json")))
    r["kind"] = s["kind"]; r["trials"] += 1
    r["pass"] += 1 if s["pass"] else 0
    r["blocker"] += 1 if s.get("all_as_blocker") else 0
if not rows:
    print("no trials under %s" % out); sys.exit(0)
print("%-34s %-11s %-8s %-10s %-10s %-6s %-6s %s" % ("case", "kind", "scored", "pass", "as-blocker", "dirty", "failed", "tokens new/read"))
for cid, r in sorted(rows.items()):
    n = r["trials"]
    label = "not-blocked" if r["kind"] == "control" else "found"
    print("%-34s %-11s %-8d %-10s %-10s %-6d %-6d %dk/%dk  (%s)" % (
        cid, r["kind"] or "?", n, "%d/%d %s" % (r["pass"], n, label),
        "-" if r["kind"] == "control" else "%d/%d" % (r["blocker"], n),
        r["contaminated"], r["failed"], r["tokens_new"] // 1000, r["tokens_read"] // 1000,
        ",".join(sorted(r["models"]))))
PY
}

# ---------------------------------------------------------------------------------------------
# run: N fresh trials. Each trial builds its own packet, spawns a read-only claude -p Challenger
# in it, extracts the structured verdict and usage, audits tool paths, and scores.
# ---------------------------------------------------------------------------------------------
resolve_model() {
  python3 -I - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
policy = json.load(open(os.path.join(root, "config/model-policy.v2.json")))
tier = policy["roles"]["challenger"]["default_tier"]
runtime = json.load(open(os.path.join(root, "config/runtimes/claude.json")))
print(runtime["tiers"][tier]["model"])
PY
}

do_run() {
  [ "$#" -ge 2 ] || usage
  local case_file="$1" out="$2"; shift 2
  local trials=1 model=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --trials) [ "$#" -ge 2 ] || usage; trials="$2"; shift 2 ;;
      --model)  [ "$#" -ge 2 ] || usage; model="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  case "$trials" in ''|*[!0-9]*) die "--trials must be a positive integer" ;; esac
  [ "$trials" -ge 1 ] || die "--trials must be a positive integer"
  [ -n "$model" ] || model="$(resolve_model)"
  local claude_bin="${CLAUDE_BIN:-claude}"
  command -v "$claude_bin" >/dev/null 2>&1 || die "Claude CLI not found: $claude_bin" 6
  local cid
  cid="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$case_file")" \
    || die "cannot read case id from $case_file"
  local system_prompt="You are The Challenger, replayed on a fixed review packet for framework evaluation. The packet in your working directory is your entire review world. Do not load CLAUDE.md or act as the Conductor."
  local t=1 rc=0 failed=0
  while [ "$t" -le "$trials" ]; do
    local stamp dir packet
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    dir="$out/$cid/trial-$stamp-$model-$t"
    mkdir -p "$dir"
    packet="$dir/packet"
    set +e
    do_build "$case_file" "$packet" > /dev/null
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      printf '{"status":"build-refused","exit":%d,"model":"%s"}\n' "$rc" "$model" > "$dir/trial.json"
      return "$rc"
    fi
    set +e
    (
      cd "$packet" &&
      "$claude_bin" -p \
        --system-prompt "$system_prompt" \
        --model "$model" \
        --output-format stream-json --verbose \
        --json-schema "$(cat "$SCHEMA")" \
        --tools "Read,Grep,Glob" \
        --add-dir "$packet" \
        --setting-sources "" \
        --no-session-persistence \
        --max-turns "${REPLAY_MAX_TURNS:-200}" \
        "$(cat BRIEF.md)" < /dev/null
    ) > "$dir/events.jsonl" 2> "$dir/stderr.log"
    rc=$?
    set -e
    do_audit "$packet" "$dir/events.jsonl" > "$dir/audit.json"
    python3 -I - "$dir" "$model" "$rc" <<'PY'
import json, os, sys
d, model, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
result = None
for line in open(os.path.join(d, "events.jsonl"), encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    if isinstance(ev, dict) and ev.get("type") == "result":
        result = ev
verdict = result.get("structured_output") if isinstance(result, dict) else None
audit = json.load(open(os.path.join(d, "audit.json")))
meta = {"model": model, "cli_exit": rc,
        "usage": (result or {}).get("usage"),
        "num_turns": (result or {}).get("num_turns"),
        "duration_ms": (result or {}).get("duration_ms"),
        "subtype": (result or {}).get("subtype")}
if audit["contaminated"]:
    meta["status"] = "contaminated"
elif rc != 0 or not isinstance(verdict, dict):
    meta["status"] = "reviewer-failed"
else:
    meta["status"] = "verdict"
    json.dump(verdict, open(os.path.join(d, "verdict.json"), "w"), indent=2, ensure_ascii=False)
json.dump(meta, open(os.path.join(d, "trial.json"), "w"), indent=2)
print(meta["status"])
PY
    local status
    status="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$dir/trial.json")"
    if [ "$status" = "verdict" ]; then
      do_score "$case_file" "$dir/verdict.json" > "$dir/score.json"
      python3 -I - "$dir/trial.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["status"] = "scored"
json.dump(m, open(p, "w"), indent=2)
PY
      status=scored
    fi
    rm -rf "${packet:?}/tree"   # reproducible from git; keep BRIEF, diff, persona, packet.json
    echo "$cid trial $t ($model): $status -> $dir"
    if [ "$status" = "reviewer-failed" ]; then failed=$((failed + 1)); fi
    t=$((t + 1))
  done
  if [ "$failed" -gt 0 ]; then
    echo "reference-replay: $failed of $trials trials returned no verdict (see stderr.log)" >&2
    return 6
  fi
  return 0
}

case "$cmd" in
  build)   do_build "$@" ;;
  run)     do_run "$@" ;;
  audit)   do_audit "$@" ;;
  score)   do_score "$@" ;;
  summary) do_summary "$@" ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac
