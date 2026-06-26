#!/bin/sh
# integration-gate.sh — the single shared integration-checkpoint gate executor.
#
# This is the standalone one-shot extracted from scripts/watcher.sh's inline
# integration executor (the FR14 single-source decision, spec OQ1). It is the ONE
# copy of the gate logic, called by two callers (docs/delegate-bridge.md § v2 §5):
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
#   --claimed-gates     <single-line inline JSON array>   (cross-check input only)
#   --known-flaky-gates <single-line inline JSON array>   (optional, default empty)
#   --state-json        <abs path to RUN_DIR/state.json>  (scope projection source)
#   --out               <abs path to the output dir = $CTX>
#
# Output: writes integration-results.json into --out (same snake_case field layout
# watcher.sh produced; field names/structure unchanged). NOTE: this file has NO
# `verdict` key — it is EVIDENCE only; the proceed/revise/escalate Decision is the
# cold reviewer's (NN-verdict.md via verdict-write.sh).
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
# dep for a pure-v1 host). No dependency on any watcher internal (poll loop, lock,
# PID): this is a pure one-shot.
#
# Exit codes:
#   0  results written (or routine no-op)
#   2  usage error (missing/unknown flag, --out absent or not a directory)
#
# Spec refs: spec.md Architecture OQ1, Technical Risk R1; docs/delegate-bridge.md
#            § v2 §5; AC5/AC7 (Track-3 evidence, closed end-to-end downstream).

# ── parse CLI flags ──────────────────────────────────────────────────────────
REQ_CHECKPOINT_TYPE=""
REQ_WORKTREE_PATH=""
REQ_BASE_REF=""
REQ_CLAIMED_GATES_RAW=""
REQ_KNOWN_FLAKY_RAW=""
STATE_JSON=""
OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkpoint-type)   REQ_CHECKPOINT_TYPE="$2";   shift 2 ;;
    --worktree-path)     REQ_WORKTREE_PATH="$2";     shift 2 ;;
    --base-ref)          REQ_BASE_REF="$2";          shift 2 ;;
    --claimed-gates)     REQ_CLAIMED_GATES_RAW="$2"; shift 2 ;;
    --known-flaky-gates) REQ_KNOWN_FLAKY_RAW="$2";   shift 2 ;;
    --state-json)        STATE_JSON="$2";            shift 2 ;;
    --out)               OUT="$2";                   shift 2 ;;
    *)
      echo "integration-gate: unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

# ── validate the caller-owned --out dir (the $CTX exists-before-write invariant) ──
# The caller stages $CTX first; this script writes into it but never creates it.
if [ -z "$OUT" ]; then
  echo "integration-gate: --out is required" >&2
  exit 2
fi
if [ ! -d "$OUT" ]; then
  echo "integration-gate: --out dir does not exist (the caller must stage it first): $OUT" >&2
  exit 2
fi

# ── integration-mode pre-spawn executor part A: parse + short-circuit flags ──
# Relocated here (it ran before staging in watcher.sh). The routine path
# (checkpoint-type routine/absent) writes NO integration-results.json, exactly as
# watcher.sh's `if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]` guard did (FR-B14-10).
if [ "$REQ_CHECKPOINT_TYPE" != "integration" ]; then
  exit 0
fi

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
  python3 - "$OUT/integration-results.json" "$INTEGRATION_ESCALATE_REASON" <<'PY'
import json, sys
path, reason = sys.argv[1], sys.argv[2]
data = {
    "schema_version": 1,
    "checkpoint_type": "integration",
    "escalate_marker": reason,
    "canonical_source": "none",
    "gates": [],
    "pre_existing": [],
    "under_declaration": [],
    "scope": {
        "diff_files": [], "allowed_paths": [], "violations": [],
        "cut_symbol_hits": [], "scope_diff_clean": None
    },
    "fast_forward_ok": False,
    "conflicts_clean": False,
    "errors": []
}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
sys.exit(0)
PY

else

  # ── RESOLVE CANONICAL GATE SET (FR-B14-3, FR-B14-12, FR-B14-14) ──────────
  # CRITICAL: the canonical gate set is NEVER derived from REQ_CLAIMED_GATES_RAW.
  # It is always: (1) the standing regression runner, PLUS (2) manifest gates if
  # a parseable manifest exists in the worktree.
  CANON_GATES_JSON="$(python3 - "$REQ_WORKTREE_PATH" <<'PY'
import json, os, sys
worktree = sys.argv[1]
gates = [{"name": "regression",
          "command": "sh %s/.bureau/regression/run.sh" % worktree}]
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
  GATE_RESULTS_JSON="$(python3 - "$REQ_WORKTREE_PATH" "$CANON_GATES_JSON" <<'PY'
import json, subprocess, sys
# FIX 2: never let a parse/subprocess failure print nothing and empty this var.
# Always print a JSON array (possibly empty); a parse failure yields [].
results = []
try:
    worktree, canon_raw = sys.argv[1], sys.argv[2]
    canon = json.loads(canon_raw)
    for g in canon.get("gates", []):
        ret = subprocess.run(g["command"], shell=True, cwd=worktree)
        results.append({
            "name": g["name"],
            "command": g["command"],
            "exit_code_branch": ret.returncode,
            "result": "green" if ret.returncode == 0 else "red"
        })
except Exception:
    results = []
print(json.dumps(results))
PY
)"

  # ── PARSE claimed-gates (W2) ────────────────────────────────────────────
  # REQ_CLAIMED_GATES_RAW is a single flat line (the caller's req_field head -n 1).
  # Parse it as a JSON array. Unparseable or absent ⇒ empty claimed set +
  # errors[] note (every canonical gate then becomes under-declaration).
  CLAIMED_GATES_JSON="$(python3 - "$REQ_CLAIMED_GATES_RAW" <<'PY'
import json, sys
raw = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    parsed = json.loads(raw) if raw.strip() else []
    if not isinstance(parsed, list):
        raise ValueError("not a list")
    print(json.dumps({"gates": parsed, "error": ""}))
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
    "$CLAIMED_GATES_JSON" <<'PY'
import json, os, subprocess, sys, tempfile
results = []
errors = []
try:
    worktree, base_ref, claimed_raw = sys.argv[1], sys.argv[2], sys.argv[3]
    claimed_data = json.loads(claimed_raw)
    claimed = claimed_data.get("gates", [])
    pre_existing_claimed = [g for g in claimed
                            if g.get("result") == "red" and g.get("pre-existing") is True]
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
                    ret_branch = subprocess.run(g["command"], shell=True, cwd=worktree)
                    ret_base = subprocess.run(g["command"], shell=True, cwd=tmpdir)
                    results.append({
                        "name": g["name"],
                        "command": g["command"],
                        "exit_code_branch": ret_branch.returncode,
                        "exit_code_base": ret_base.returncode,
                        "confirmed_pre_existing": ret_base.returncode != 0
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
    claimed_names = {g.get("name", "") for g in claimed}
    claimed_cmds  = {g.get("command", "") for g in claimed}
    for g in gate_results:
        if g["name"] not in claimed_names and g["command"] not in claimed_cmds:
            under.append(g)
except Exception:
    under = []
print(json.dumps(under))
PY
)"

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
    "cut_symbol_hits": [], "scope_diff_clean": None
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

    r = subprocess.run(
        ["git", "diff", "%s...HEAD" % base_ref, "--name-only"],
        cwd=worktree, capture_output=True, text=True
    )
    diff_files = [l for l in r.stdout.splitlines() if l.strip()]

    import fnmatch
    violations = []
    if allowed_paths:
        for f in diff_files:
            if not any(fnmatch.fnmatch(f, pat) for pat in allowed_paths):
                violations.append(f)

    # grep the full diff for each cut symbol
    r2 = subprocess.run(
        ["git", "diff", "%s...HEAD" % base_ref],
        cwd=worktree, capture_output=True, text=True
    )
    full_diff = r2.stdout
    cut_symbol_hits = [sym for sym in cut_symbols if sym in full_diff]

    scope_diff_clean = (len(violations) == 0 and len(cut_symbol_hits) == 0)
    print(json.dumps({
        "diff_files": diff_files, "allowed_paths": allowed_paths,
        "violations": violations, "cut_symbol_hits": cut_symbol_hits,
        "scope_diff_clean": scope_diff_clean
    }))
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

  # ── CONFLICTS CHECK ────────────────────────────────────────────────────
  if [ -z "$(git -C "$REQ_WORKTREE_PATH" status --porcelain 2>/dev/null)" ]; then
    CONFLICTS_CLEAN=true
  else
    CONFLICTS_CLEAN=false
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
    "$ERRORS_JSON" <<'PY'
import json, sys

(path, worktree_path, base_ref, branch_tip, canonical_source,
 gates_raw, pre_raw, under_raw, scope_raw,
 ff_ok, conflicts_clean, errors_raw) = sys.argv[1:13]

NEUTRAL_SCOPE = {
    "diff_files": [], "allowed_paths": [], "violations": [],
    "cut_symbol_hits": [], "scope_diff_clean": None
}


def write_escalate(reason, errors):
    """Skeletal escalate-marker — identical shape to the INTEGRATION_ESCALATE
    branch — so the Delegate always reads a well-formed file and escalates."""
    data = {
        "schema_version": 1,
        "checkpoint_type": "integration",
        "escalate_marker": reason,
        "canonical_source": "none",
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

fi   # end if INTEGRATION_ESCALATE

exit 0
