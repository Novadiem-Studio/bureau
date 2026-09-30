#!/bin/sh
# integration-gate.sh — the single shared integration-checkpoint gate executor.
#
# This is the standalone one-shot extracted from scripts/watcher.sh's inline
# integration executor (the FR14 single-source decision, spec OQ1). It is the ONE
# copy of the gate logic, called by two callers (docs/delegate-bridge/v2-integrated.md § v2 §5):
#   - the v2 Delegate (manager mode) before spawning the cold reviewer at an
#     integration checkpoint;
#   - the refactored v1 watcher (Phase 4 / Prompt 4), in place of its inline body.
#
# "The build cannot grade its own homework" (FR14): the caller (the Delegate / the
# watcher), never the Conductor/build, runs this. The canonical gate set is resolved
# from the PROJECT'S OWN runners/manifest — NEVER from claimed-gates: the verified
# party does not define what gets executed.
#
# CLI flags:
#   --checkpoint-type   <routine|integration>   routine => no-op, exit 0
#   --worktree-path     <abs path or "(none)">
#   --base-ref          <git ref>
#   --claimed-gates     <single-line inline JSON array of {"name","command",...}
#                        objects>   (cross-check input only). A bare-string element
#                        is NOT a valid claim: it is dropped (never crashes) and
#                        recorded in errors[] instead of silently counting toward
#                        canonical-gate declaration (issue #74).
#   --known-flaky-gates <single-line inline JSON array>   (optional, default empty)
#   --state-json        <abs path to RUN_DIR/state.json>  (scope projection source)
#   --out               <abs path to the output dir = $CTX>
#
# Gate-mode flags (issue #92). All optional; the default is the full local suite,
# exactly as before, so the v1 watcher and older callers are unchanged:
#   --gate-mode   <local|ci>   local (default) runs the canonical gate set in the
#                   worktree. ci confirms `gh pr checks` is fully green on the
#                   worktree's exact HEAD instead, and falls back to local (with
#                   the reason recorded) whenever CI cannot stand in for it:
#                   --final, a merge commit since --since-ref, no known PR, no gh,
#                   or no checks reported on the head commit.
#   --final         this is the final/terminal gate: always the local suite.
#   --since-ref   <git ref>    the commit the previous integration gate verified.
#                   A merge commit in since-ref..HEAD forces the local suite (the
#                   first gate after merging main). Unresolvable => local.
#   --pr          <number|url> the pull request whose checks to read. Default:
#                   state.json#git.pr_number.
#   --repo        <OWNER/REPO> passed to gh as -R. Default: state.json#git.github_repo.
#   --ci-timeout  <seconds>    deadline for CI to finish (default 3600). Pending
#                   is a wait, never a pass: at the deadline it records red.
#   --ci-poll     <seconds>    poll interval (default 30).
#   --ci-no-checks-grace <seconds>  how long to wait for a first check to appear
#                   on the head commit before concluding it has no CI (default 300).
#
# Output: writes integration-results.json into --out (same snake_case field layout
# watcher.sh produced; issue #92 adds gate_mode, gate_mode_requested,
# gate_mode_reason, gate_commands and ci, and keeps every existing field). NOTE:
# this file has NO `verdict` key — it is EVIDENCE only; the proceed/revise/escalate
# Decision is the cold reviewer's (NN-verdict.md via verdict-write.sh).
#
# Kept output (issue #92): every gate's stdout and stderr stream straight into
# --out/gate-output/ (<gate>.stdout.log / <gate>.stderr.log; ci-poll.log and
# ci-checks.json in CI mode), and each gate record carries the paths plus a short
# tail. A red gate can always be diagnosed from the checkpoint dir, and a gate that
# is killed mid-run still leaves what it printed. run-cold-reviewer.sh leaves
# gate-output/ out of the reviewer's artifact manifest.
#
# OWNERSHIP INVARIANT (the part-A/part-B ordering, R1): in watcher.sh, part A (parse
# + short-circuit guards) ran BEFORE the CTX staging block, and part B (the executor
# body) ran AFTER $CTX existed. Here the refactor relocates part A to run INSIDE this
# script after its own setup; part B is the body. The logic is UNCHANGED — only the
# position of part A relative to staging moves. The CALLER stages --out first and
# this script writes into it; this script does NOT mkdir --out (the caller owns it).
# It checks --out exists and fails clearly if not, preserving "$CTX exists before any
# write into it".
#
# Deps: POSIX sh + python3 + git — exactly what watcher.sh already required (no new
# dep for a pure-v1 host). CI mode also uses gh when it is on PATH; without it the
# gate records the reason and runs the local suite. No dependency on any watcher
# internal (poll loop, lock, PID): this is a pure one-shot.
#
# Exit codes:
#   0  results written (or routine no-op)
#   2  usage error (missing/unknown flag, --out absent or not a directory)
#
# Spec refs: spec.md Architecture OQ1, Technical Risk R1;
#            docs/delegate-bridge/v2-integrated.md § v2 §5;
#            AC5/AC7 (Track-3 evidence, closed end-to-end downstream).

# ── parse CLI flags ──────────────────────────────────────────────────────────
REQ_CHECKPOINT_TYPE=""
REQ_WORKTREE_PATH=""
REQ_BASE_REF=""
REQ_CLAIMED_GATES_RAW=""
REQ_KNOWN_FLAKY_RAW=""
STATE_JSON=""
OUT=""
REQ_GATE_MODE="local"
REQ_FINAL=0
REQ_SINCE_REF=""
REQ_PR=""
REQ_REPO=""
CI_TIMEOUT=3600
CI_POLL=30
CI_NO_CHECKS_GRACE=300

while [ "$#" -gt 0 ]; do
  case "$1" in
    --final)             REQ_FINAL=1; shift; continue ;;
  esac
  if [ "$#" -lt 2 ]; then
    echo "integration-gate: flag $1 needs a value" >&2
    exit 2
  fi
  case "$1" in
    --checkpoint-type)   REQ_CHECKPOINT_TYPE="$2";   shift 2 ;;
    --worktree-path)     REQ_WORKTREE_PATH="$2";     shift 2 ;;
    --base-ref)          REQ_BASE_REF="$2";          shift 2 ;;
    --claimed-gates)     REQ_CLAIMED_GATES_RAW="$2"; shift 2 ;;
    --known-flaky-gates) REQ_KNOWN_FLAKY_RAW="$2";   shift 2 ;;
    --state-json)        STATE_JSON="$2";            shift 2 ;;
    --out)               OUT="$2";                   shift 2 ;;
    --gate-mode)         REQ_GATE_MODE="$2";         shift 2 ;;
    --since-ref)         REQ_SINCE_REF="$2";         shift 2 ;;
    --pr)                REQ_PR="$2";                shift 2 ;;
    --repo)              REQ_REPO="$2";              shift 2 ;;
    --ci-timeout)        CI_TIMEOUT="$2";            shift 2 ;;
    --ci-poll)           CI_POLL="$2";               shift 2 ;;
    --ci-no-checks-grace) CI_NO_CHECKS_GRACE="$2";   shift 2 ;;
    *)
      echo "integration-gate: unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

# ── routine short-circuit: a routine checkpoint is a true no-op ──────────────
# watcher.sh's `if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]` guard skipped the
# whole executor for routine/absent — no integration-results.json, no $CTX needed.
# This runs BEFORE the --out check so a routine call is a pure no-op (exit 0) that
# requires no --out, matching watcher.sh's behavior (FR-B14-10) and the README
# contract ("routine => no-op, exit 0, no file").
if [ "$REQ_CHECKPOINT_TYPE" != "integration" ]; then
  exit 0
fi

# ── validate the gate-mode flags (issue #92) ─────────────────────────────────
case "$REQ_GATE_MODE" in
  local|ci) ;;
  *) echo "integration-gate: --gate-mode must be local or ci, not: $REQ_GATE_MODE" >&2; exit 2 ;;
esac
for _n in "$CI_TIMEOUT" "$CI_POLL" "$CI_NO_CHECKS_GRACE"; do
  case "$_n" in
    ''|*[!0-9]*) echo "integration-gate: --ci-timeout/--ci-poll/--ci-no-checks-grace take whole seconds, not: $_n" >&2; exit 2 ;;
  esac
done

# ── validate the caller-owned --out dir (the $CTX exists-before-write invariant) ──
# Integration checkpoints only. The caller stages $CTX first; this script writes
# into it but never creates it.
if [ -z "$OUT" ]; then
  echo "integration-gate: --out is required for an integration checkpoint" >&2
  exit 2
fi
if [ ! -d "$OUT" ]; then
  echo "integration-gate: --out dir does not exist (the caller must stage it first): $OUT" >&2
  exit 2
fi
# Preflight writability (nice-to-have — the post-write assertion below is the
# must). A write into an unwritable --out fails silently otherwise (F2): the
# Python heredoc raises PermissionError but the shell still reaches `exit 0`,
# reporting SUCCESS with NO evidence file. Catch the common case early.
if [ ! -w "$OUT" ]; then
  echo "integration-gate: --out dir is not writable: $OUT" >&2
  exit 2
fi

# ── FAIL-CLOSED post-write assertion (F2) ─────────────────────────────────────
# integration-results.json is the Delegate's verifying-mode source of truth, and
# it has NO "file absent → escalate" contract, so a gate that exits 0 having
# written NOTHING is a silent SUCCESS-with-no-evidence. Every heredoc that is
# meant to write $OUT/integration-results.json is followed by a call to this: it
# verifies the file exists, is non-empty, AND parses as JSON; if any check fails
# it prints a clear stderr reason and exits 2 (a distinct fail-closed code). A
# write failure can therefore NEVER reach the `exit 0` at the foot of this script.
assert_results_written() {
  _res="$OUT/integration-results.json"
  if [ ! -s "$_res" ]; then
    echo "integration-gate: FAIL-CLOSED — expected evidence file absent or empty after write: $_res (write likely failed, e.g. unwritable --out); exiting 2 rather than reporting a false SUCCESS" >&2
    exit 2
  fi
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_res" 2>/dev/null; then
    echo "integration-gate: FAIL-CLOSED — evidence file is not valid JSON after write: $_res; exiting 2 rather than reporting a false SUCCESS" >&2
    exit 2
  fi
}

# ── integration-mode pre-spawn executor part A: parse + short-circuit flags ──
# Relocated here (it ran before staging in watcher.sh). Logic unchanged.
INTEGRATION_ESCALATE=0
INTEGRATION_ESCALATE_REASON=""

# SHORT-CIRCUIT GUARD 1 — (none)-worktree (EC-B14-1, AC-8):
if [ -z "$REQ_WORKTREE_PATH" ] || [ "$REQ_WORKTREE_PATH" = "(none)" ]; then
  INTEGRATION_ESCALATE=1
  INTEGRATION_ESCALATE_REASON="No worktree available for integration verification; re-run after providing worktree-path."

# SHORT-CIRCUIT GUARD 2 — unresolvable base-ref (EC-B14-4, AC-9):
elif ! git -C "$REQ_WORKTREE_PATH" rev-parse "$REQ_BASE_REF" > /dev/null 2>&1; then
  INTEGRATION_ESCALATE=1
  INTEGRATION_ESCALATE_REASON="base-ref not resolvable; cannot validate pre-existing claims."
fi

# ── integration-mode pre-spawn executor part B: write results + task prompt ──
# $OUT (= $CTX) was validated above. All file writes targeting $OUT happen here.
if [ "$INTEGRATION_ESCALATE" = "1" ]; then

  # Write the skeletal-but-present escalate-marker block so:
  # (a) verdict-write.sh integration-evidence presence guard is satisfied,
  # (b) the Delegate reads a well-formed file and emits a well-formed verdict,
  # (c) the Delegate's verifying-mode trigger (file presence) fires correctly.
  python3 - "$OUT/integration-results.json" "$INTEGRATION_ESCALATE_REASON" "$REQ_GATE_MODE" <<'PY'
import json, sys
path, reason, requested = sys.argv[1], sys.argv[2], sys.argv[3]
data = {
    "schema_version": 1,
    "checkpoint_type": "integration",
    "escalate_marker": reason,
    "canonical_source": "none",
    "gate_mode": "none",
    "gate_mode_requested": requested,
    "gate_mode_reason": "no gate ran: escalate marker set",
    "gate_commands": [],
    "ci": None,
    "gates": [],
    "pre_existing": [],
    "under_declaration": [],
    "scope": {
        "diff_files": [], "allowed_paths": [], "violations": [],
        "cut_symbol_hits": [], "cut_symbol_introduced": [], "cut_symbol_attribution": {},
        "scope_diff_clean": None
    },
    "fast_forward_ok": False,
    "conflicts_clean": False,
    "errors": []
}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
sys.exit(0)
PY
  # F2: fail closed if the escalate-marker write did not land on disk.
  assert_results_written

else

  # ── KEPT OUTPUT DIR (issue #92) ────────────────────────────────────────
  # Every gate streams stdout/stderr here. $OUT was checked writable above, so a
  # failure to create it is a real filesystem fault: fail closed.
  GATE_OUT_DIR="$OUT/gate-output"
  if ! mkdir -p "$GATE_OUT_DIR"; then
    echo "integration-gate: cannot create the kept-output dir $GATE_OUT_DIR; exiting 2 rather than running a gate whose output would be lost" >&2
    exit 2
  fi

  # ── RESOLVE THE GATE MODE, AND IN CI MODE READ THE CHECKS (issue #92) ──
  # Prints one JSON object: {"mode": "ci"|"local", "requested", "reason",
  # "ci": {...}|null, "gate": {...}|null}. "ci" mode means CI decided this gate
  # (green or red). Anything that stops CI standing in for the suite resolves to
  # "local" with the reason, and the canonical local gates run below.
  #
  # PENDING IS NEVER PASS: a check still queued or running is a wait. If the
  # deadline arrives first the gate is red (exit_code_branch 124,
  # ci.status pending_timeout). The head commit is bound on both sides of the
  # checks read: gh pr view's headRefOid must equal the worktree HEAD before and
  # after `gh pr checks`, so the checks read belong to exactly this commit.
  MODE_JSON="$(python3 - "$REQ_GATE_MODE" "$REQ_WORKTREE_PATH" "$REQ_SINCE_REF" \
    "$REQ_FINAL" "$REQ_PR" "$REQ_REPO" "$STATE_JSON" "$CI_TIMEOUT" "$CI_POLL" \
    "$CI_NO_CHECKS_GRACE" "$GATE_OUT_DIR" <<'PY'
import json, os, shutil, subprocess, sys, time

(requested, worktree, since_ref, final, pr, repo, state_path,
 timeout_s, poll_s, grace_s, outdir) = sys.argv[1:12]
timeout_s, poll_s, grace_s = int(timeout_s), max(int(poll_s), 1), int(grace_s)
res = {"mode": "local", "requested": requested, "reason": "", "ci": None, "gate": None}
poll_log = os.path.join(outdir, "ci-poll.log")


def log(msg):
    line = "%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg)
    sys.stderr.write("integration-gate: %s\n" % msg)
    try:
        with open(poll_log, "a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def done(mode, reason):
    res["mode"], res["reason"] = mode, reason
    print(json.dumps(res))
    sys.exit(0)


def git(*args):
    return subprocess.run(["git", "-C", worktree] + list(args),
                          capture_output=True, text=True)


try:
    if requested != "ci":
        done("local", "local mode requested")
    if final == "1":
        done("local", "final gate: the full local suite always runs at the final or terminal gate")

    if not pr or not repo:
        try:
            with open(state_path) as fh:
                g = (json.load(fh) or {}).get("git") or {}
            pr = pr or ("" if g.get("pr_number") in (None, "") else str(g.get("pr_number")))
            repo = repo or (g.get("github_repo") or "")
        except Exception:
            pass
    if not pr:
        done("local", "no pull request known (no --pr and no state.json git.pr_number), so CI cannot stand in; ran the local suite")

    if since_ref:
        merges = git("rev-list", "--merges", "%s..HEAD" % since_ref)
        if merges.returncode != 0:
            done("local", "--since-ref %s is not resolvable, so a merge since the last gate cannot be ruled out; ran the local suite" % since_ref)
        found = merges.stdout.split()
        if found:
            done("local", "merge commit(s) since the last gate (%s): the first gate after a merge runs the full local suite"
                 % ", ".join(s[:12] for s in found))

    gh = shutil.which("gh")
    if gh is None:
        done("local", "gh is not on PATH, so CI checks cannot be read; ran the local suite")

    head = git("rev-parse", "HEAD")
    if head.returncode != 0:
        done("local", "cannot read the worktree HEAD; ran the local suite")
    local_sha = head.stdout.strip()

    repo_args = ["-R", repo] if repo else []
    view_cmd = [gh, "pr", "view", pr] + repo_args + ["--json", "headRefOid", "-q", ".headRefOid"]
    checks_cmd = [gh, "pr", "checks", pr] + repo_args + ["--json", "name,state,bucket,workflow,link"]
    shown_cmd = " ".join(["gh"] + checks_cmd[1:])

    def pr_head():
        r = subprocess.run(view_cmd, capture_output=True, text=True)
        if r.returncode != 0:
            return None, (r.stderr or r.stdout).strip()
        return r.stdout.strip(), ""

    def poll_once():
        """-> (status, checks, detail). status is one of passed, failed,
        pending, head_mismatch, no_checks, gh_error."""
        h1, err = pr_head()
        if h1 is None:
            return "gh_error", [], "gh pr view failed: %s" % err
        if h1 != local_sha:
            return "head_mismatch", [], "PR head is %s, worktree HEAD is %s (not pushed yet?)" % (h1[:12], local_sha[:12])
        r = subprocess.run(checks_cmd, capture_output=True, text=True)
        if "no checks reported" in (r.stderr + r.stdout).lower():
            return "no_checks", [], "gh reports no checks on the head commit"
        try:
            checks = json.loads(r.stdout)
            if not isinstance(checks, list):
                raise ValueError("not a list")
        except Exception:
            return "gh_error", [], "gh pr checks gave no JSON (exit %d): %s" % (r.returncode, (r.stderr or r.stdout).strip()[:300])
        try:
            with open(os.path.join(outdir, "ci-checks.json"), "w") as fh:
                json.dump(checks, fh, indent=2)
        except OSError:
            pass
        h2, err = pr_head()
        if h2 != h1:
            return "head_mismatch", checks, "PR head moved during the read (%s -> %s)" % (h1[:12], (h2 or "?")[:12])
        buckets = [c.get("bucket") for c in checks if isinstance(c, dict)]
        if any(b in ("fail", "cancel") for b in buckets):
            return "failed", checks, ""
        if any(b not in ("pass", "skipping") for b in buckets):
            return "pending", checks, ""
        if "pass" in buckets:
            return "passed", checks, ""
        return "no_checks", checks, "no check on the head commit passed or is pending (all skipped or none)"

    start = time.time()
    deadline, grace_deadline = start + timeout_s, start + grace_s
    polls, gh_errors, status, checks, detail = 0, 0, None, [], ""
    log("CI mode: reading checks for PR %s%s at %s (deadline %ds)" % (pr, " in " + repo if repo else "", local_sha[:12], timeout_s))
    while True:
        polls += 1
        status, checks, detail = poll_once()
        waiting_on = [c.get("name") for c in checks if isinstance(c, dict)
                      and c.get("bucket") not in ("pass", "skipping", "fail", "cancel")]
        note = (" - " + detail) if detail else (" (waiting on: %s)" % ", ".join(map(str, waiting_on)) if waiting_on else "")
        log("poll %d: %s%s" % (polls, status, note))
        now = time.time()
        if status in ("passed", "failed"):
            break
        if status == "gh_error":
            gh_errors += 1
            if gh_errors >= 3:
                done("local", "gh failed 3 times in a row (%s); ran the local suite" % detail)
        else:
            gh_errors = 0
        if status == "no_checks" and (now >= grace_deadline or now >= deadline):
            done("local", "no CI on %s after %ds (%s); ran the local suite" % (local_sha[:12], int(now - start), detail))
        if now >= deadline:
            status = "pending_timeout" if status == "pending" else "%s_timeout" % status
            break
        time.sleep(max(1, min(poll_s, deadline - now)))

    waited = int(time.time() - start)
    exit_code = {"passed": 0, "failed": 1}.get(status, 124)
    summary = [{k: c.get(k) for k in ("name", "bucket", "state", "workflow", "link")}
               for c in checks if isinstance(c, dict)]
    res["ci"] = {
        "pr": pr, "repo": repo, "head_sha": local_sha, "status": status,
        "detail": detail, "polls": polls, "waited_s": waited, "deadline_s": timeout_s,
        "failed": [c["name"] for c in summary if c["bucket"] in ("fail", "cancel")],
        "pending": [c["name"] for c in summary if c["bucket"] not in ("pass", "skipping", "fail", "cancel")],
        "checks": summary,
        "checks_path": "gate-output/ci-checks.json",
        "poll_log_path": "gate-output/ci-poll.log",
    }
    res["gate"] = {
        "name": "ci",
        "command": shown_cmd,
        "exit_code_branch": exit_code,
        "result": "green" if exit_code == 0 else "red",
        "ci_status": status,
        "head_sha": local_sha,
    }
    log("CI result: %s after %ds and %d poll(s)" % (status, waited, polls))
    reason = {"passed": "CI green on the exact head commit",
              "failed": "CI red on the exact head commit (re-run with --gate-mode local if the failure needs local diagnosis)"}
    done("ci", reason.get(status, "CI did not finish on the head commit before the deadline (%s): pending is not a pass" % status))
except SystemExit:
    raise
except Exception as e:
    done("local", "CI mode failed unexpectedly (%s); ran the local suite" % e)
PY
)"
  EFFECTIVE_MODE="$(python3 -c 'import json,sys
try:
    print(json.loads(sys.argv[1]).get("mode", "local"))
except Exception:
    print("local")' "$MODE_JSON" 2>/dev/null || echo local)"
  case "$MODE_JSON" in
    "{"*) ;;
    *) MODE_JSON="{\"mode\": \"local\", \"requested\": \"$REQ_GATE_MODE\", \"reason\": \"gate-mode resolution produced no result; ran the local suite\", \"ci\": null, \"gate\": null}" ;;
  esac

  if [ "$EFFECTIVE_MODE" = "ci" ]; then
    # CI decided this gate: one "ci" gate record, no local suite run.
    # Fail closed: an unreadable CI record becomes a red gate, never an empty
    # list (an empty gates list would read as an all-clear).
    GATE_RESULTS_JSON="$(python3 -c 'import json,sys; g=json.loads(sys.argv[1])["gate"]; assert isinstance(g, dict); print(json.dumps([g]))' "$MODE_JSON" 2>/dev/null \
      || echo '[{"name": "ci", "command": "gh pr checks", "exit_code_branch": 2, "result": "red", "ci_status": "unreadable"}]')"
    CANON_GATES_JSON='{"gates": [], "canonical_source": "ci"}'
  else

  # ── RESOLVE CANONICAL GATE SET (FR-B14-3, FR-B14-12, FR-B14-14) ──────────
  # CRITICAL: the canonical gate set is NEVER derived from REQ_CLAIMED_GATES_RAW.
  # It is always: (1) the standing regression runner, PLUS (2) manifest gates if
  # a parseable manifest exists in the worktree.
  CANON_GATES_JSON="$(python3 - "$REQ_WORKTREE_PATH" <<'PY'
import json, os, sys
worktree = sys.argv[1]
gates = [{"name": "regression",
          "command": "sh %s/.bureau/regression/run.sh" % worktree,
          "runner": os.path.join(worktree, ".bureau", "regression", "run.sh")}]
manifest = os.path.join(worktree, "package.json")
canonical_source = "regression-only"
if os.path.isfile(manifest):
    try:
        with open(manifest) as fh:
            pkg = json.load(fh)
        scripts = pkg.get("scripts", {})
        gate_keys = [k for k in ("build", "typecheck", "test") if k in scripts]
        for k in gate_keys:
            gates.append({"name": "npm-%s" % k, "command": "npm run %s" % k})
        if gate_keys:
            canonical_source = "regression+manifest"
    except Exception:
        pass
print(json.dumps({"gates": gates, "canonical_source": canonical_source}))
PY
)"

  # ── RUN EACH CANONICAL GATE at branch tip ──────────────────────────────
  # Read gates list; run each command in the worktree; capture exit codes.
  GATE_RESULTS_JSON="$(python3 - "$REQ_WORKTREE_PATH" "$CANON_GATES_JSON" "$GATE_OUT_DIR" <<'PY'
import hashlib, json, os, re, subprocess, sys, time
# FIX 2: never let a parse/subprocess failure print nothing and empty this var.
# Always print a JSON array (possibly empty); a parse failure yields [].


def tail(path, n=30, width=400):
    try:
        with open(path, "rb") as fh:
            lines = fh.read().decode("utf-8", "replace").splitlines()
        return [l[:width] for l in lines[-n:]]
    except OSError:
        return []


results = []
try:
    worktree, canon_raw, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    canon = json.loads(canon_raw)
    for g in canon.get("gates", []):
        # FIX (defect 1): the gate's stdout/stderr must never inherit this python
        # process's stdout — which IS the `$(...)` the shell captures into
        # GATE_RESULTS_JSON. A chatty gate (e.g. jest printing ~74KB) would
        # prepend non-JSON to the captured string; the downstream json.loads
        # then fails and gates collapses to [] — a silent false all-clear.
        # Issue #92: instead of capturing and discarding, both streams go
        # straight to files in the kept-output dir, so a red gate can be
        # diagnosed and a gate killed mid-run still leaves what it printed.
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", g["name"]) or "gate"
        out_rel = "gate-output/%s.stdout.log" % slug
        err_rel = "gate-output/%s.stderr.log" % slug
        out_path = os.path.join(outdir, os.path.basename(out_rel))
        err_path = os.path.join(outdir, os.path.basename(err_rel))
        t0 = time.time()
        output_error = None
        try:
            with open(out_path, "wb") as fo, open(err_path, "wb") as fe:
                ret = subprocess.run(g["command"], shell=True, cwd=worktree,
                                     stdout=fo, stderr=fe)
        except OSError as e:
            # Never let a log-file problem drop the gate (an empty gates list
            # would read as an all-clear): run it captured, and say so.
            output_error = "could not keep output: %s" % e
            ret = subprocess.run(g["command"], shell=True, cwd=worktree,
                                 capture_output=True)
        entry = {
            "name": g["name"],
            "command": g["command"],
            "exit_code_branch": ret.returncode,
            "result": "green" if ret.returncode == 0 else "red",
            "duration_s": int(time.time() - t0),
            "stdout_path": out_rel,
            "stderr_path": err_rel,
            "stdout_tail": tail(out_path),
            "stderr_tail": tail(err_path, 20),
        }
        if output_error:
            entry["output_error"] = output_error
        # The runner file can switch suites (fast vs full) with no change to
        # the command string, so record its digest, and the suite it names
        # when it prints a `BUREAU-SUITE: <command>` line.
        runner = g.get("runner")
        if runner and os.path.isfile(runner):
            with open(runner, "rb") as fh:
                entry["runner_path"] = runner
                entry["runner_sha256"] = hashlib.sha256(fh.read()).hexdigest()
        suite = [l.split(":", 1)[1].strip() for l in tail(out_path, 100000, 2000)
                 if l.startswith("BUREAU-SUITE:")]
        if suite:
            entry["suite"] = suite[-1]
        results.append(entry)
except Exception:
    results = []
print(json.dumps(results))
PY
)"

  fi   # end gate-mode branch (ci records its one gate above; local ran the suite)

  # ── PARSE claimed-gates (W2) ────────────────────────────────────────────
  # REQ_CLAIMED_GATES_RAW is a single flat line (the caller's req_field head -n 1).
  # Parse it as a JSON array. Unparseable or absent ⇒ empty claimed set +
  # errors[] note (every canonical gate then becomes under-declaration).
  #
  # ELEMENT SHAPE (issue #74): every element must be an object with name/command
  # keys to count as a claim — a bare string is coerced out downstream by the
  # isinstance(dict) guards in the pre-existing-red validation and the
  # under-declaration cross-check below (that behavior is pinned by
  # .bureau/regression/237-integration-gate-string-claimed-gate.md and must not
  # change). What WAS missing: when every element is a bare string, both guards
  # silently empty the whole claimed set, every canonical gate lands in
  # under_declaration, and errors[] stayed [] — a false comprehensive
  # under-declaration with no diagnostic. Record the shape problem here instead,
  # so it is visible in integration-results.json rather than masquerading as a
  # real under-declaration.
  CLAIMED_GATES_JSON="$(python3 - "$REQ_CLAIMED_GATES_RAW" <<'PY'
import json, sys
raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    parsed = json.loads(raw) if raw.strip() else []
    if not isinstance(parsed, list):
        raise ValueError("not a list")
    bad = sum(1 for g in parsed if not isinstance(g, dict))
    if bad:
        err = ("claimed-gates elements must be objects with name/command; got "
               "%d bare (non-object) element(s) — they do not count as a "
               "declared gate" % bad)
    else:
        err = ""
    print(json.dumps({"gates": parsed, "error": err}))
except Exception as e:
    print(json.dumps({"gates": [], "error": "claimed-gates not parseable as JSON: %s" % e}))
PY
)"

  # ── PARSE known-flaky-gates (OQ-B14-4) ────────────────────────────────
  # Parse the optional known-flaky-gates field. When present, a canonical gate
  # whose re-run result is red AND whose name appears in known-flaky-gates is
  # DEMOTED: the result is recorded but marked flaky, and the Delegate flags it
  # in Uncertainties rather than blocking on it (OQ-B14-4 decision).
  # Absent or unparseable ⇒ empty list (every re-run red blocks — the
  # conservative default). This is a membership test against a declared list,
  # not open-ended severity reasoning (FR-44 boundary).
  KNOWN_FLAKY_JSON="$(python3 - "$REQ_KNOWN_FLAKY_RAW" <<'PY'
import json, sys
raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    parsed = json.loads(raw) if raw.strip() else []
    names = [e.get("name", "") for e in parsed if isinstance(e, dict)]
    print(json.dumps(names))
except Exception:
    print(json.dumps([]))
PY
)"

  # ── VALIDATE claimed-pre-existing reds at base-ref (FR-B14-4) ─────────
  # For each claimed gate with result: "red" AND pre-existing: true, re-run
  # its command at base-ref to confirm whether the red is genuine or a
  # mislabeled regression.
  #
  # BASE-REF EXECUTION — correct approach only:
  # Do NOT git checkout or git stash in the main worktree (that would alter
  # the branch under review). Instead, create a temporary separate git worktree
  # at the base ref (DETACHED — see FIX 1 below), run the gate command there,
  # then remove it.
  #   git -C "$REQ_WORKTREE_PATH" worktree add --detach "$TMPDIR_BASE" "$REQ_BASE_REF"
  #   <run command in $TMPDIR_BASE>
  #   git -C "$REQ_WORKTREE_PATH" worktree remove --force "$TMPDIR_BASE"
  #
  # FIX 1 — `--detach`: when base-ref is a branch already checked out elsewhere
  # (the common case: base-ref `main` with `main` checked out in the main repo),
  # a plain `worktree add <dir> <branch>` FAILS ("already checked out"). A
  # detached add checks out the ref's commit at a detached HEAD, which works even
  # when the branch is checked out elsewhere — and is correct here (we only read).
  #
  # FIX 2 — every fallible step (worktree add, gate subprocesses, JSON parse) is
  # wrapped so a failure yields a SAFE value (empty pre_existing list + an
  # errors[] note) instead of an uncaught exception that prints nothing and
  # empties this variable — which would crash the final json.loads and leave NO
  # integration-results.json staged. This script ALWAYS prints a JSON object
  # {"results": [...], "errors": [...]}; downstream reads .results / .errors.
  PRE_EXISTING_JSON="$(python3 - \
    "$REQ_WORKTREE_PATH" \
    "$REQ_BASE_REF" \
    "$CLAIMED_GATES_JSON" \
    "$GATE_OUT_DIR" <<'PY'
import json, os, re, subprocess, sys, tempfile
results = []
errors = []
try:
    worktree, base_ref, claimed_raw, outdir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    claimed_data = json.loads(claimed_raw)
    claimed = claimed_data.get("gates", [])
    pre_existing_claimed = [g for g in claimed
                            if isinstance(g, dict) and g.get("result") == "red" and g.get("pre-existing") is True]
    if pre_existing_claimed:
        tmpdir = tempfile.mkdtemp(prefix="bureau-base-")
        added = False
        try:
            # FIX 1: --detach so a checked-out base branch does not fail the add.
            add = subprocess.run(
                ["git", "-C", worktree, "worktree", "add", "--detach", tmpdir, base_ref],
                capture_output=True, text=True
            )
            if add.returncode != 0:
                # FIX 2: do not raise — record the failure and fall through to a
                # safe (empty) result. The final write still happens; if this
                # leaves the overall executor unable to validate, the guarded
                # final write below escalates rather than crashing.
                errors.append("base-ref worktree add failed: %s"
                              % (add.stderr.strip() or "unknown error"))
            else:
                added = True
                for g in pre_existing_claimed:
                    # FIX (defect 1, same class as the canonical-gate loop):
                    # capture_output=True so a verbose claimed-pre-existing gate
                    # cannot contaminate the `$(...)` this heredoc feeds into
                    # PRE_EXISTING_JSON. Only the returncodes are consumed.
                    # Issue #92: both runs stream into the kept-output dir
                    # (never the stdout of this process, which feeds the capture).
                    slug = re.sub(r"[^A-Za-z0-9._-]", "_", str(g.get("name", ""))) or "gate"
                    paths = {}
                    rcs = {}
                    for side, cwd in (("branch", worktree), ("base", tmpdir)):
                        o = os.path.join(outdir, "pre-existing-%s.%s.stdout.log" % (slug, side))
                        e = os.path.join(outdir, "pre-existing-%s.%s.stderr.log" % (slug, side))
                        with open(o, "wb") as fo, open(e, "wb") as fe:
                            rcs[side] = subprocess.run(g["command"], shell=True, cwd=cwd,
                                                       stdout=fo, stderr=fe).returncode
                        paths[side] = ["gate-output/" + os.path.basename(o),
                                       "gate-output/" + os.path.basename(e)]
                    results.append({
                        "name": g["name"],
                        "command": g["command"],
                        "exit_code_branch": rcs["branch"],
                        "exit_code_base": rcs["base"],
                        "confirmed_pre_existing": rcs["base"] != 0,
                        "output_paths": paths
                    })
        finally:
            if added:
                subprocess.run(
                    ["git", "-C", worktree, "worktree", "remove", "--force", tmpdir],
                    capture_output=True
                )
            if os.path.exists(tmpdir):
                import shutil; shutil.rmtree(tmpdir, ignore_errors=True)
except Exception as e:
    # Any unexpected failure yields a safe value (empty results) plus a note,
    # never an uncaught exception that empties this variable downstream.
    errors.append("pre-existing validation failed: %s" % e)
print(json.dumps({"results": results, "errors": errors}))
PY
)"

  # ── UNDER-DECLARATION cross-check (FR-B14-14) ─────────────────────────
  # Compute canonical_gates − claimed_gates (match on name or command).
  # Records all canonical gates the build did not declare.
  # In CI mode the one gate is the CI read, which the build cannot declare, and
  # no local gate ran to cross-check against the claims, so the check is empty.
  if [ "$EFFECTIVE_MODE" = "ci" ]; then
  UNDER_DECL_JSON='[]'
  else
  UNDER_DECL_JSON="$(python3 - \
    "$GATE_RESULTS_JSON" \
    "$CLAIMED_GATES_JSON" <<'PY'
import json, sys
# FIX 2: guarded — always prints a JSON array (empty on any failure).
under = []
try:
    gate_results = json.loads(sys.argv[1])
    claimed_data = json.loads(sys.argv[2])
    claimed = claimed_data.get("gates", [])
    claimed_names = {g.get("name", "") for g in claimed if isinstance(g, dict)}
    claimed_cmds  = {g.get("command", "") for g in claimed if isinstance(g, dict)}
    for g in gate_results:
        if g["name"] not in claimed_names and g["command"] not in claimed_cmds:
            under.append(g)
except Exception:
    under = []
print(json.dumps(under))
PY
)"
  fi

  # ── SCOPE DIFF (FR-B14-5) ──────────────────────────────────────────────
  SCOPE_JSON="$(python3 - \
    "$REQ_WORKTREE_PATH" \
    "$REQ_BASE_REF" \
    "$STATE_JSON" <<'PY'
import json, subprocess, sys
# FIX 2: the whole step is guarded — a git/parse failure prints a valid
# "indeterminate" scope object (scope_diff_clean: null), never nothing.
NEUTRAL = {
    "diff_files": [], "allowed_paths": [], "violations": [],
    "cut_symbol_hits": [], "cut_symbol_introduced": [], "cut_symbol_attribution": {},
        "scope_diff_clean": None
}
try:
    worktree, base_ref, state_path = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        with open(state_path) as fh:
            state = json.load(fh)
        scope_block = state.get("scope") or {}
        allowed_paths = scope_block.get("allowed_paths") or []
        cut_symbols = scope_block.get("cut_symbols") or []
    except Exception:
        scope_block = None
        allowed_paths = []
        cut_symbols = []

    if scope_block is None:
        print(json.dumps(NEUTRAL))
        sys.exit(0)

    import re
    # Pin every diff to plain, prefixed, uncoloured output so user or repo git
    # config (color.diff=always, diff.noprefix, an external diff driver, a
    # textconv filter, diff.submodule=log) cannot change what the parser sees. Output is read as
    # bytes: text=True would turn a lone CR inside a line into a line break.
    GIT_DIFF = ["git", "-c", "core.quotePath=true", "diff", "--no-color",
                "--no-ext-diff", "--no-textconv", "--no-relative",
                "--src-prefix=a/", "--dst-prefix=b/", "--submodule=short"]
    def git_diff(args):
        res = subprocess.run(GIT_DIFF + ["%s...HEAD" % base_ref] + args,
                             cwd=worktree, capture_output=True)
        if res.returncode != 0:
            raise RuntimeError("git diff %s failed" % " ".join(args))
        return res.stdout
    def nul_paths(raw):
        return [p.decode("utf-8", "replace") for p in raw.split(b"\0") if p]

    diff_files = nul_paths(git_diff(["--name-only", "-z"]))
    # Paths this range brings into existence (added, copied, renamed-to).
    new_paths = nul_paths(git_diff(["--name-only", "-z", "--diff-filter=ACR"]))

    import fnmatch
    violations = []
    if allowed_paths:
        for f in diff_files:
            if not any(fnmatch.fnmatch(f, pat) for pat in allowed_paths):
                violations.append(f)

    # Content is decoded leniently: cut symbols are matched as text, and a
    # non-UTF-8 byte must not abort the scan into the non-blocking null result.
    patch = git_diff([]).decode("utf-8", "replace")

    kinds = ("added", "removed", "context", "header", "path")
    def decode_git_quoted_path(inner):
        out = bytearray()
        i = 0
        escapes = {
            "a": b"\a", "b": b"\b", "f": b"\f", "n": b"\n",
            "r": b"\r", "t": b"\t", "v": b"\v", "\\": b"\\", '"': b'"'
        }
        while i < len(inner):
            ch = inner[i]
            if ch != "\\":
                out.extend(ch.encode("utf-8"))
                i += 1
                continue
            i += 1
            if i >= len(inner):
                out.extend(b"\\")
                break
            esc = inner[i]
            if esc in "01234567":
                j = i
                while j < len(inner) and j < i + 3 and inner[j] in "01234567":
                    j += 1
                out.append(int(inner[i:j], 8))
                i = j
                continue
            out.extend(escapes.get(esc, esc.encode("utf-8")))
            i += 1
        return out.decode("utf-8")

    def parse_diff_path(token, side):
        path = token.strip()
        if path.startswith('"') and path.endswith('"'):
            inner = path[1:-1]
            try:
                path = decode_git_quoted_path(inner)
            except Exception:
                path = inner
        prefix = "b/" if side == "new" else "a/"
        if path.startswith(prefix):
            path = path[2:]
        return None if path == "/dev/null" else path

    cut_symbol_attribution = {
        sym: {"total": {k: 0 for k in kinds}, "files": {}}
        for sym in cut_symbols
    }
    hit_symbols = set()
    added_hit_symbols = set()

    def record(sym, path, kind):
        sym_data = cut_symbol_attribution[sym]
        sym_data["total"][kind] += 1
        file_counts = sym_data["files"].setdefault(path, {k: 0 for k in kinds})
        file_counts[kind] += 1
        hit_symbols.add(sym)
        if kind in ("added", "path"):
            added_hit_symbols.add(sym)

    # A new file whose own path names a cut symbol introduces it as surely as
    # an added line does.
    for path in new_paths:
        for sym in cut_symbols:
            if sym in path:
                record(sym, path, "path")

    # Hunk bodies are delimited by the line counts in each @@ header, never by
    # guessing from the leading characters of a line. Every line of the patch must
    # be accounted for: a hunk line consumes its count, and anything outside a
    # hunk must be a known git header. A line the parser cannot place makes the
    # scope result fail closed (scope_diff_clean false) instead of going unscanned.
    HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")
    FILE_HEADERS = ("index ", "old mode ", "new mode ", "deleted file mode ",
                    "new file mode ", "similarity index ", "dissimilarity index ",
                    "rename from ", "rename to ", "copy from ", "copy to ",
                    "Binary files ", "GIT binary patch")
    parse_error = None
    current_file = None
    current_old_file = None
    old_left = new_left = 0
    parsed_added = parsed_removed = 0
    lines = patch.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for lineno, line in enumerate(lines, 1):
        if old_left > 0 or new_left > 0:
            first = line[:1]
            if first == "+" and new_left > 0:
                kind, text = "added", line[1:]
                new_left -= 1
                parsed_added += 1
            elif first == "-" and old_left > 0:
                kind, text = "removed", line[1:]
                old_left -= 1
                parsed_removed += 1
            elif first in (" ", "") and old_left > 0 and new_left > 0:
                # "" is a blank context line under diff.suppressBlankEmpty.
                kind, text = "context", line[1:]
                old_left -= 1
                new_left -= 1
            elif first == "\\":
                continue
            else:
                parse_error = "line %d does not fit the open hunk" % lineno
                break
        elif line.startswith("diff --git "):
            current_file = None
            current_old_file = None
            continue
        elif line.startswith("--- "):
            current_old_file = parse_diff_path(line[4:], "old")
            continue
        elif line.startswith("+++ "):
            current_new_file = parse_diff_path(line[4:], "new")
            current_file = current_new_file if current_new_file is not None else current_old_file
            continue
        elif line.startswith("@@"):
            m = HUNK.match(line)
            if not m or current_file is None:
                parse_error = "line %d is an unparseable hunk header" % lineno
                break
            old_left = int(m.group(1)) if m.group(1) is not None else 1
            new_left = int(m.group(2)) if m.group(2) is not None else 1
            kind, text = "header", line[m.end():]
        elif line.startswith("\\") or line.startswith(FILE_HEADERS):
            continue
        else:
            parse_error = "line %d is outside any hunk and is not a git header" % lineno
            break
        for sym in cut_symbols:
            if sym in text:
                record(sym, current_file, kind)
    if parse_error is None and (old_left > 0 or new_left > 0):
        parse_error = "patch ended inside a hunk"

    # Invariant: the parser saw exactly the added and removed line totals git
    # reports. A mismatch means some lines were never classified.
    if parse_error is None:
        want_added = want_removed = 0
        for row in git_diff(["--numstat"]).decode("utf-8", "replace").split("\n"):
            cols = row.split("\t")
            if len(cols) >= 3 and cols[0] != "-":
                want_added += int(cols[0])
                want_removed += int(cols[1])
        if (want_added, want_removed) != (parsed_added, parsed_removed):
            parse_error = "parsed +%d/-%d lines but git reports +%d/-%d" % (
                parsed_added, parsed_removed, want_added, want_removed)

    cut_symbol_hits = [sym for sym in cut_symbols if sym in hit_symbols]
    cut_symbol_added_hits = [sym for sym in cut_symbols if sym in added_hit_symbols]

    # Scope asks what this run introduced: only added-line and new-path
    # cut-symbol hits fail. A patch the parser could not fully account for
    # fails too, because unscanned lines cannot be called clean.
    scope_diff_clean = (len(violations) == 0 and len(cut_symbol_added_hits) == 0
                        and parse_error is None)
    result = {
        "diff_files": diff_files, "allowed_paths": allowed_paths,
        "violations": violations, "cut_symbol_hits": cut_symbol_hits,
        "cut_symbol_introduced": cut_symbol_added_hits,
        "cut_symbol_attribution": cut_symbol_attribution,
        "scope_diff_clean": scope_diff_clean
    }
    if parse_error is not None:
        result["parse_error"] = parse_error
    print(json.dumps(result))
except Exception:
    print(json.dumps(NEUTRAL))
PY
)"

  # ── FAST-FORWARD CHECK (FR-B14-6, BLOCKER 1) ──────────────────────────
  # Command: git -C <worktree> merge-base --is-ancestor "<base-ref>" HEAD
  # Semantics: exit 0 iff <base-ref> is an ancestor of the branch tip HEAD,
  # i.e. the branch already contains the base ⇒ fast-forwardable.
  # Non-zero ⇒ base is NOT an ancestor of HEAD (base has advanced/diverged)
  # ⇒ fast_forward_ok: false ⇒ Delegate emits revise "rebase required".
  # Operand order is "<base-ref>" HEAD — base as FIRST operand, HEAD second.
  # DO NOT use: merge-base HEAD <base-ref> (wrong direction);
  # DO NOT nest merge-base inside --is-ancestor (that produces the tautology).
  if git -C "$REQ_WORKTREE_PATH" merge-base --is-ancestor "$REQ_BASE_REF" HEAD 2>/dev/null; then
    FF_OK=true
  else
    FF_OK=false
  fi

  # ── CONFLICTS CHECK (defect 2) ─────────────────────────────────────────
  # Semantics: "would integrating base..HEAD produce merge conflicts?" — NOT
  # "is the working tree dirty". The old test was `git status --porcelain`,
  # which reports ANY dirty/untracked file (e.g. the Delegate's own untracked
  # .bureau/regression/run.sh), so it falsely returned conflicts_clean=false
  # while FF_OK=true — a self-contradiction that Step 4 turns into a bogus
  # "unresolved merge conflicts" revise. Untracked/dirty working-tree files
  # must NEVER count as conflicts.
  #
  # Test (mirrors the FAST-FORWARD-CHECK style above):
  #  1. Fast-forwardable case: if FF_OK=true then base IS an ancestor of HEAD,
  #     so integrating base..HEAD is a pure fast-forward with NO conflicts by
  #     definition ⇒ conflicts_clean=true. This also guarantees the invariant
  #     "ff-ok ⇒ conflicts-clean" (the two fields can never contradict).
  #  2. Non-ff case: run a REAL 3-way merge test with `git merge-tree`.
  #     Prefer the modern `git merge-tree --write-tree` (git ≥ 2.38): it does a
  #     real merge and EXITS NON-ZERO (1) iff there are conflicts, 0 iff clean.
  #     Fall back (git < 2.38, or when BUREAU_FORCE_LEGACY_MERGETREE=1 forces it
  #     for test coverage) to the classic 3-arg `git merge-tree <mergebase>
  #     <branch1> <branch2>` form, which ALWAYS exits 0 and marks conflicts
  #     inline in its diff output. Two things the classic form requires, both of
  #     which the first cut of this fix got wrong and are verified here against
  #     real `git merge-tree` output:
  #       (a) arg 1 must be the TRUE common ancestor `git merge-base <base> HEAD`
  #           — NOT base itself. Passing base as its own merge-base makes HEAD's
  #           change look like the only divergence, so git resolves it as a clean
  #           two-way change and never emits markers (a real conflict then reads
  #           as clean — the exact silent all-clear this run exists to kill).
  #       (b) classic merge-tree prefixes conflict-hunk lines with `+` in its
  #           diff, so a genuine conflict shows `+<<<<<<< .our` — an anchored
  #           `^<<<<<<< ` pattern can NEVER match it. Match `^+<<<<<<<`.
  #     Neither merge-tree form touches the working tree, so untracked/dirty
  #     files cannot register as conflicts.
  #
  # BUREAU_FORCE_LEGACY_MERGETREE=1 skips the modern `--write-tree` path so the
  # legacy fallback is reachable under regression on a modern git (mirrors the
  # BUREAU_* test-injection convention, e.g. BUREAU_POINTER_FILE / BUREAU_ACCOUNT_RUN_SH).
  if [ "$FF_OK" = "true" ]; then
    CONFLICTS_CLEAN=true
  else
    MT_RC=2   # sentinel: "modern path not run" → go straight to legacy fallback
    if [ "${BUREAU_FORCE_LEGACY_MERGETREE:-0}" != "1" ]; then
      # Modern `--write-tree` merge test: exit 0 = clean, 1 = conflicts, other
      # (e.g. 128 when the flag is unsupported) = fall through to legacy.
      git -C "$REQ_WORKTREE_PATH" merge-tree --write-tree \
        "$REQ_BASE_REF" HEAD >/dev/null 2>&1
      MT_RC=$?
    fi
    if [ "$MT_RC" = "0" ]; then
      CONFLICTS_CLEAN=true
    elif [ "$MT_RC" = "1" ]; then
      CONFLICTS_CLEAN=false
    else
      # Classic fallback: TRUE merge-base as arg 1, and match the `+`-prefixed
      # conflict marker the classic diff emits (see (a)/(b) above).
      MB="$(git -C "$REQ_WORKTREE_PATH" merge-base "$REQ_BASE_REF" HEAD 2>/dev/null)"
      if [ -n "$MB" ] && git -C "$REQ_WORKTREE_PATH" merge-tree \
           "$MB" "$REQ_BASE_REF" HEAD 2>/dev/null \
           | grep -q '^+<<<<<<<'; then
        CONFLICTS_CLEAN=false
      else
        CONFLICTS_CLEAN=true
      fi
    fi
  fi

  # ── BRANCH TIP SHA ────────────────────────────────────────────────────
  BRANCH_TIP="$(git -C "$REQ_WORKTREE_PATH" rev-parse HEAD 2>/dev/null || echo unknown)"

  # ── APPLY known-flaky-gates demotion to GATE_RESULTS_JSON ─────────────
  # Any gate in the known-flaky-gates list whose result is "red" gets marked
  # "flaky: true" so the Delegate flags it in Uncertainties rather than blocking.
  GATE_RESULTS_JSON="$(python3 - "$GATE_RESULTS_JSON" "$KNOWN_FLAKY_JSON" <<'PY'
import json, sys
# FIX 2: guarded — on any failure, echo arg1 through unchanged (or [] if that
# too is unparseable) so this never empties GATE_RESULTS_JSON downstream.
try:
    gates = json.loads(sys.argv[1])
    flaky_names = set(json.loads(sys.argv[2]))
    for g in gates:
        if g.get("result") == "red" and g.get("name") in flaky_names:
            g["flaky"] = True
    print(json.dumps(gates))
except Exception:
    try:
        print(json.dumps(json.loads(sys.argv[1])))
    except Exception:
        print("[]")
PY
)"

  # ── WRITE integration-results.json to $OUT ────────────────────────────
  # FIX 3: build the seed errors[] with json.dumps, never shell string-concat —
  # a quote/newline in the claimed-gates parse error can no longer produce
  # malformed JSON. This is only the SEED list; the final python step appends
  # any pre-existing-validation errors it finds in $PRE_EXISTING_JSON.
  ERRORS_JSON="$(python3 -c 'import json,sys
try:
    err = json.loads(sys.argv[1]).get("error", "")
except Exception:
    err = ""
print(json.dumps([err] if err else []))' "$CLAIMED_GATES_JSON" 2>/dev/null || echo "[]")"

  CANON_SOURCE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('canonical_source','regression-only'))" "$CANON_GATES_JSON" 2>/dev/null || echo "regression-only")"

  # ── GUARDED FINAL WRITE — the invariant lives here ─────────────────────
  # FIX 2: this is the ONLY exit from the integration path, and it ALWAYS
  # writes a well-formed $OUT/integration-results.json. Each intermediate JSON
  # is parsed defensively; if any one is empty/garbage (an upstream step that
  # somehow failed despite its own guard), this step writes the SKELETAL
  # ESCALATE-MARKER file — same shape as the INTEGRATION_ESCALATE branch above:
  # escalate_marker set with the reason, empty arrays, fast_forward_ok /
  # conflicts_clean false — so the Delegate reads a valid file and escalates
  # (surfacing the failure to a human) rather than silently falling through.
  # There is no code path between "$OUT exists" and here that can leave the
  # file unwritten: any exception is caught and converted to an escalate file.
  python3 - \
    "$OUT/integration-results.json" \
    "$REQ_WORKTREE_PATH" \
    "$REQ_BASE_REF" \
    "$BRANCH_TIP" \
    "$CANON_SOURCE" \
    "$GATE_RESULTS_JSON" \
    "$PRE_EXISTING_JSON" \
    "$UNDER_DECL_JSON" \
    "$SCOPE_JSON" \
    "$FF_OK" \
    "$CONFLICTS_CLEAN" \
    "$ERRORS_JSON" \
    "$MODE_JSON" <<'PY'
import json, sys

(path, worktree_path, base_ref, branch_tip, canonical_source,
 gates_raw, pre_raw, under_raw, scope_raw,
 ff_ok, conflicts_clean, errors_raw, mode_raw) = sys.argv[1:14]

NEUTRAL_SCOPE = {
    "diff_files": [], "allowed_paths": [], "violations": [],
    "cut_symbol_hits": [], "cut_symbol_introduced": [], "cut_symbol_attribution": {},
        "scope_diff_clean": None
}


def write_escalate(reason, errors):
    """Skeletal escalate-marker — identical shape to the INTEGRATION_ESCALATE
    branch — so the Delegate always reads a well-formed file and escalates."""
    data = {
        "schema_version": 1,
        "checkpoint_type": "integration",
        "escalate_marker": reason,
        "canonical_source": "none",
        "gate_mode": "none",
        "gate_mode_requested": mode.get("requested", ""),
        "gate_mode_reason": "no usable gate result: escalate marker set",
        "gate_commands": [],
        "ci": mode.get("ci"),
        "gates": [],
        "pre_existing": [],
        "under_declaration": [],
        "scope": dict(NEUTRAL_SCOPE),
        "fast_forward_ok": False,
        "conflicts_clean": False,
        "errors": errors,
    }
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)


try:
    mode = json.loads(mode_raw)
    if not isinstance(mode, dict):
        raise ValueError("not an object")
except Exception:
    mode = {"mode": "local", "requested": "", "reason": "gate-mode record unreadable", "ci": None}

try:
    errors = json.loads(errors_raw) if errors_raw.strip() else []
    if not isinstance(errors, list):
        errors = []

    # pre_raw is now {"results": [...], "errors": [...]}; tolerate a bare list
    # or empty/garbage. Any failure here demotes to the escalate path below.
    try:
        pre_parsed = json.loads(pre_raw) if pre_raw.strip() else {"results": [], "errors": []}
    except Exception:
        pre_parsed = {"results": [], "errors": []}
    if isinstance(pre_parsed, dict):
        pre_existing = pre_parsed.get("results", []) or []
        errors.extend(pre_parsed.get("errors", []) or [])
    elif isinstance(pre_parsed, list):
        pre_existing = pre_parsed
    else:
        pre_existing = []

    def safe(raw, default):
        try:
            return json.loads(raw) if raw.strip() else default
        except Exception:
            errors.append("malformed intermediate JSON; result coerced to safe default")
            return default

    gates = safe(gates_raw, [])
    under = safe(under_raw, [])
    scope = safe(scope_raw, dict(NEUTRAL_SCOPE))

    data = {
        "schema_version": 1,
        "checkpoint_type": "integration",
        "worktree_path": worktree_path,
        "base_ref": base_ref,
        "branch_tip": branch_tip,
        "escalate_marker": "",
        "canonical_source": canonical_source or "regression-only",
        # Issue #92: which mode produced this result, why, and the exact
        # commands behind it (the regression runner's digest and any
        # BUREAU-SUITE line sit on its gate record).
        "gate_mode": mode.get("mode", "local"),
        "gate_mode_requested": mode.get("requested", ""),
        "gate_mode_reason": mode.get("reason", ""),
        "gate_commands": [g.get("command", "") for g in gates if isinstance(g, dict)],
        "ci": mode.get("ci"),
        "gates": gates,
        "pre_existing": pre_existing,
        "under_declaration": under,
        "scope": scope,
        "fast_forward_ok": ff_ok == "true",
        "conflicts_clean": conflicts_clean == "true",
        "errors": errors,
    }
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
except Exception as e:
    # Last-resort guard: anything unexpected still yields a well-formed escalate
    # file. The invariant holds — a file is ALWAYS on disk for an integration cp.
    try:
        write_escalate(
            "integration executor failed to assemble results: %s; escalated for human review" % e,
            ["integration executor exception: %s" % e],
        )
    except Exception:
        # Filesystem-level failure (e.g. $OUT gone) — re-raise so the caller's
        # own error handling surfaces it; there is nothing safe left to write.
        raise
PY
  # F2: fail closed if the final results write did not land on disk. Covers both
  # the ordinary write path and the last-resort escalate-file write above: if the
  # heredoc's Python re-raised (filesystem-level failure), the shell does not
  # `set -e`, so control falls through to here — and this assertion converts that
  # into exit 2 instead of the false SUCCESS the bare `exit 0` below would give.
  assert_results_written

fi   # end if INTEGRATION_ESCALATE

exit 0
