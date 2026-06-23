#!/bin/sh
# The Delegate watcher — the poll loop, locking, staging, and Delegate spawn.
#
# Watches RUN_DIR/checkpoints for NN-request.md files. For each unclaimed request
# it: claims an atomic mkdir lock, stages the per-checkpoint read set into a
# scratch context dir, spawns the Delegate headless against ONLY that context dir,
# and on the Delegate's exit calls verdict-write.sh (validate + cap + atomic write
# + ledger append). It then tears down the context dir and the lock.
#
# Three invariants are gated at review and must not regress:
#   1. Identity isolation (EC1): the spawn uses --bare + --system-prompt naming
#      The Delegate, so the "you are the Conductor" CLAUDE.md rule can never fire.
#   2. Log isolation (EC8): the spawn reads ONLY the staged context dir via
#      --add-dir "$CTX" — never the whole run dir. log.md is never copied into
#      $CTX, and after staging we assert log.md is absent from it.
#   3. Re-entrancy (EC3): the request is claimed with an atomic `mkdir NN.lock`
#      BEFORE staging. Two poll passes (or two watchers) can never spawn two
#      delegates for one request. A request that already has NN-verdict.md is
#      skipped (FR 38). A lock whose PID is dead is reclaimed on startup.
#
# Environment (set by delegate-launcher.sh):
#   RUN_DIR           absolute path to the run dir (also accepted as $1)
#   ROOT              absolute path to the agent-framework root
#   DELEGATE_MAX_USD  per-checkpoint spend ceiling (default 0.50)
#   REVISION_CAP      revision cap integer (default 2)
#
# Usage:
#   watcher.sh [RUN_DIR]
#
# Exit codes:
#   0  clean exit (SIGTERM trapped)
#   1  bad configuration (RUN_DIR / ROOT missing or invalid)
#
# Spec refs: docs/delegate-bridge.md § 3 (spawn invocation), § 4 (staging),
#            § 7 (bridge failure modes); AC 7, AC 13, AC 14; EC1, EC3, EC8.

# ── configuration ────────────────────────────────────────────────────────────

# $1 overrides $RUN_DIR for CLI convenience (delegate-launcher.sh passes it both
# ways).
if [ -n "$1" ]; then
  RUN_DIR="$1"
fi

if [ -z "$RUN_DIR" ]; then
  echo "watcher: RUN_DIR is not set (pass as \$1 or export it)" >&2
  exit 1
fi
if [ ! -d "$RUN_DIR" ]; then
  echo "watcher: RUN_DIR is not a directory: $RUN_DIR" >&2
  exit 1
fi

# ROOT defaults to two levels up from this script (scripts/ -> ROOT) so the
# watcher works from any checkout without delegate-launcher.sh exporting it.
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
if [ ! -d "$ROOT" ]; then
  echo "watcher: ROOT is not a directory: $ROOT" >&2
  exit 1
fi

DELEGATE_MAX_USD="${DELEGATE_MAX_USD:-0.50}"
REVISION_CAP="${REVISION_CAP:-2}"
# Per-checkpoint spawn-failure ceiling (money-safety). --max-budget-usd caps the
# spend of ONE spawn but NOT the number of spawns. If the Delegate persistently
# emits invalid/empty JSON, verdict-write.sh fails closed (no verdict) and the
# poll loop would otherwise re-spawn `claude` every poll forever — unbounded
# spend. After this many consecutive failed spawns for one NN, give up on that
# request: escalate, mark it failed, and stop re-spawning.
MAX_SPAWN_FAILURES="${MAX_SPAWN_FAILURES:-3}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKPOINTS_DIR="$RUN_DIR/checkpoints"
POLL_INTERVAL=2

# ── clean SIGTERM exit (and SIGINT) ──────────────────────────────────────────
# The launcher kills the watcher with SIGTERM at teardown; exit cleanly.

watcher_running=1
on_term() {
  watcher_running=0
  echo "watcher: received termination signal — exiting" >&2
  exit 0
}
trap on_term TERM INT

# ── helpers ──────────────────────────────────────────────────────────────────

# Read one "key: value" line from a request file; strip key + surrounding space.
req_field() {
  # $1 = key, $2 = file
  grep -E "^$1:[[:space:]]*" "$2" 2>/dev/null \
    | head -n 1 \
    | sed -E "s/^$1:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

# Match the bare `artifact:` key but NOT `artifact-hash:` (anchor on the colon
# being immediately followed by whitespace or end-of-line).
req_artifact() {
  grep -E '^artifact:[[:space:]]' "$1" 2>/dev/null \
    | head -n 1 \
    | sed -E 's/^artifact:[[:space:]]*//' \
    | sed -E 's/[[:space:]]+$//'
}

# Is the given PID alive? `kill -0` returns 0 if a signal could be sent.
pid_alive() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

# Resolve the Delegate model name. Prefer RUN_DIR/model-routing.json
# roles.delegate.model; fall back to a tier->model map on roles.delegate.tier;
# fall back to "opus" if the role or the file is missing (strong tier on Claude).
resolve_delegate_model() {
  routing="$RUN_DIR/model-routing.json"
  model=""
  if [ -f "$routing" ]; then
    model="$(python3 - "$routing" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
role = (d.get("roles") or {}).get("delegate") or {}
m = role.get("model")
if m:
    print(m); sys.exit(0)
tier = role.get("tier")
tier_map = {"standard": "sonnet", "strong": "opus", "frontier": "opus", "escalated": "opus"}
if tier in tier_map:
    print(tier_map[tier]); sys.exit(0)
PY
)"
  fi
  [ -n "$model" ] || model="opus"
  printf '%s' "$model"
}

# ── stale-lock reclaim on startup (EC3) ──────────────────────────────────────
# On startup, scan existing lock dirs. A lock whose PID is dead belonged to a
# crashed watcher — remove it so the request can be reclaimed by the poll loop.
# A lock whose PID is alive belongs to a live watcher and is left alone.

reclaim_stale_locks() {
  [ -d "$CHECKPOINTS_DIR" ] || return 0
  for lockdir in "$CHECKPOINTS_DIR"/*.lock; do
    [ -d "$lockdir" ] || continue
    lock_pid=""
    [ -f "$lockdir/pid" ] && lock_pid="$(cat "$lockdir/pid" 2>/dev/null)"
    if pid_alive "$lock_pid"; then
      continue
    fi
    echo "watcher: reclaiming stale lock (dead pid '${lock_pid:-none}'): $lockdir" >&2
    rm -rf "$lockdir"
  done
}

# ── process one request ──────────────────────────────────────────────────────
# Returns silently; all failures are logged to stderr and never abort the loop.

process_request() {
  request_file="$1"
  base="$(basename "$request_file")"
  NN="${base%-request.md}"

  verdict_file="$CHECKPOINTS_DIR/$NN-verdict.md"
  lock_dir="$CHECKPOINTS_DIR/$NN.lock"
  failcount_file="$CHECKPOINTS_DIR/$NN.failcount"
  failed_marker="$CHECKPOINTS_DIR/$NN.failed"

  # Skip a request that already has a verdict (FR 38). The 'verdict.md' token
  # here is also the static guard fixture 05 greps for.
  if [ -f "$verdict_file" ]; then
    return 0
  fi

  # Skip a request that has been given up on (W1 poison marker): the Delegate
  # failed to produce a valid verdict MAX_SPAWN_FAILURES times in a row, so we
  # stopped re-spawning to bound spend. Attended intervention is needed.
  if [ -f "$failed_marker" ]; then
    return 0
  fi

  # If a lock already exists, honour it unless its PID is dead (crashed watcher).
  # Reclaim a dead-PID lock by atomic steal-by-rename (EC3 race close): `mv` of a
  # dir is atomic on the same filesystem, so exactly one racing watcher wins the
  # rename and owns the reclaim. A loser's `mv` fails (source already gone) and it
  # skips. The winner verifies the moved lock's PID is still dead, removes it, and
  # falls through to the normal atomic mkdir claim below.
  if [ -d "$lock_dir" ]; then
    lock_pid=""
    [ -f "$lock_dir/pid" ] && lock_pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    if pid_alive "$lock_pid"; then
      return 0
    fi
    reclaiming="$lock_dir.reclaiming.$$"
    if ! mv "$lock_dir" "$reclaiming" 2>/dev/null; then
      # Another watcher stole the dead lock first — skip this pass.
      return 0
    fi
    # We own the reclaim. Re-confirm the moved lock's PID is still dead; if it has
    # somehow come back alive, restore the lock and yield to it.
    moved_pid=""
    [ -f "$reclaiming/pid" ] && moved_pid="$(cat "$reclaiming/pid" 2>/dev/null)"
    if pid_alive "$moved_pid"; then
      mv "$reclaiming" "$lock_dir" 2>/dev/null || rm -rf "$reclaiming"
      return 0
    fi
    echo "watcher: reclaimed dead lock (pid '${lock_pid:-none}') for $NN" >&2
    rm -rf "$reclaiming"
  fi

  # Atomic claim: mkdir succeeds for exactly one caller. If it fails, another
  # watcher (or a racing poll pass) won the request — skip it. This is the
  # re-entrancy guarantee: a request is staged and spawned by exactly one claim.
  if ! mkdir "$lock_dir" 2>/dev/null; then
    return 0
  fi
  echo "$$" > "$lock_dir/pid"

  # Parse the request file.
  REQ_ARTIFACT="$(req_artifact "$request_file")"
  REQ_HASH="$(req_field 'artifact-hash' "$request_file")"
  REQ_LOG_SLICE="$(req_field 'log-slice' "$request_file")"
  REQ_CHECKPOINT="$(req_field 'checkpoint' "$request_file")"
  REQ_RUN_DIR="$(req_field 'run-dir' "$request_file")"

  # Stale-request guard (FR 40): a request from a different run-dir is not ours.
  if [ -n "$REQ_RUN_DIR" ] && [ "$REQ_RUN_DIR" != "$RUN_DIR" ]; then
    echo "watcher: request $NN run-dir '$REQ_RUN_DIR' != '$RUN_DIR' — not ours, releasing" >&2
    rm -rf "$lock_dir"
    return 0
  fi

  if [ -z "$REQ_ARTIFACT" ] || [ ! -f "$REQ_ARTIFACT" ]; then
    echo "watcher: request $NN artifact missing or unreadable: '$REQ_ARTIFACT' — releasing" >&2
    rm -rf "$lock_dir"
    return 0
  fi

  # W3 collision guard: if the artifact's basename is literally log.md, the EC8
  # "remove log.md from CTX" assertion below would silently strip the artifact and
  # the Delegate would review an empty read set. Refuse to stage — escalate, warn,
  # release, and skip. (A guard, not a rename: we do not silently relocate it.)
  if [ "$(basename "$REQ_ARTIFACT")" = "log.md" ]; then
    echo "watcher: request $NN artifact basename collides with log.md — cannot stage safely, escalating" >&2
    sh "$SCRIPT_DIR/notify-escalation.sh" "$NN" "$RUN_DIR" \
      "artifact basename collides with log.md — cannot stage safely" || true
    rm -rf "$lock_dir"
    return 0
  fi

  if [ -z "$REQ_LOG_SLICE" ] || [ ! -f "$REQ_LOG_SLICE" ]; then
    echo "watcher: request $NN log-slice missing or unreadable: '$REQ_LOG_SLICE' — releasing" >&2
    rm -rf "$lock_dir"
    return 0
  fi

  # ── integration-mode pre-spawn executor part A: parse + short-circuit flags ──
  # Additive: only the integration path uses these. The routine path (checkpoint-type
  # routine/absent) leaves every variable at its default and never enters the gated
  # block below or in part B (FR-B14-10, AC-11). No file is written here — $CTX does
  # not exist until the staging block runs (part B is where $CTX writes happen).
  REQ_CHECKPOINT_TYPE="$(req_field 'checkpoint-type' "$request_file")"
  REQ_WORKTREE_PATH="$(req_field 'worktree-path' "$request_file")"
  REQ_BASE_REF="$(req_field 'base-ref' "$request_file")"
  REQ_CLAIMED_GATES_RAW="$(req_field 'claimed-gates' "$request_file")"
  REQ_KNOWN_FLAKY_RAW="$(req_field 'known-flaky-gates' "$request_file")"

  INTEGRATION_ESCALATE=0
  INTEGRATION_ESCALATE_REASON=""

  if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]; then

    # SHORT-CIRCUIT GUARD 1 — (none)-worktree (EC-B14-1, AC-8):
    if [ -z "$REQ_WORKTREE_PATH" ] || [ "$REQ_WORKTREE_PATH" = "(none)" ]; then
      INTEGRATION_ESCALATE=1
      INTEGRATION_ESCALATE_REASON="No worktree available for integration verification; re-run after providing worktree-path."

    # SHORT-CIRCUIT GUARD 2 — unresolvable base-ref (EC-B14-4, AC-9):
    elif ! git -C "$REQ_WORKTREE_PATH" rev-parse "$REQ_BASE_REF" > /dev/null 2>&1; then
      INTEGRATION_ESCALATE=1
      INTEGRATION_ESCALATE_REASON="base-ref not resolvable; cannot validate pre-existing claims."
    fi

  fi
  # If REQ_CHECKPOINT_TYPE is NOT "integration": all variables remain at defaults;
  # the integration block in part B checks REQ_CHECKPOINT_TYPE and falls through.

  # ── stage the per-checkpoint read set into NN-context (EC8) ────────────────
  # The staged dir is the Delegate's ONLY read root. log.md is NEVER copied in.
  CTX="$CHECKPOINTS_DIR/${NN}-context"
  rm -rf "$CTX"
  mkdir -p "$CTX"
  cp "$REQ_ARTIFACT"               "$CTX/"
  cp "$REQ_LOG_SLICE"              "$CTX/log-slice.md"
  cp "$RUN_DIR/state.json"         "$CTX/"
  cp "$ROOT/docs/conventions.md"   "$CTX/"
  cp "$ROOT/agents/delegate.md"    "$CTX/"

  # EC8 assertion: log.md must never be in the staged context dir. If a copy ever
  # included it (e.g. the artifact itself was named log.md, or a future edit
  # widened the staging set), remove it and warn — coldness must not break.
  if [ -e "$CTX/log.md" ]; then
    echo "watcher: WARNING — log.md present in staged context $CTX — removing (EC8 isolation)" >&2
    rm -f "$CTX/log.md"
  fi

  artifact_base="$(basename "$REQ_ARTIFACT")"

  # ── integration-mode pre-spawn executor part B: write results + task prompt ──
  # $CTX now exists (created by the staging block above) and $artifact_base is set.
  # All file writes targeting $CTX happen here. This block runs only when
  # checkpoint-type: integration; the routine path skips it untouched (FR-B14-10).
  if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]; then

    if [ "$INTEGRATION_ESCALATE" = "1" ]; then

      # Write the skeletal-but-present escalate-marker block so:
      # (a) verdict-write.sh integration-evidence presence guard is satisfied,
      # (b) the Delegate reads a well-formed file and emits a well-formed verdict,
      # (c) the Delegate's verifying-mode trigger (file presence) fires correctly.
      python3 - "$CTX/integration-results.json" "$INTEGRATION_ESCALATE_REASON" <<'PY'
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
      # REQ_CLAIMED_GATES_RAW is a single flat line from req_field (head -n 1).
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
      # DEMOTED: the watcher records the result but marks it flaky, and the Delegate
      # flags it in Uncertainties rather than blocking on it (OQ-B14-4 decision).
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
        "$RUN_DIR/state.json" <<'PY'
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

      # ── WRITE integration-results.json to $CTX ────────────────────────────
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
      # writes a well-formed $CTX/integration-results.json. Each intermediate JSON
      # is parsed defensively; if any one is empty/garbage (an upstream step that
      # somehow failed despite its own guard), this step writes the SKELETAL
      # ESCALATE-MARKER file — same shape as the INTEGRATION_ESCALATE branch above:
      # escalate_marker set with the reason, empty arrays, fast_forward_ok /
      # conflicts_clean false — so the Delegate reads a valid file and escalates
      # (surfacing the failure to a human) rather than silently falling through.
      # There is no code path between "$CTX exists" and here that can leave the
      # file unwritten: any exception is caught and converted to an escalate file.
      python3 - \
        "$CTX/integration-results.json" \
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
        # Filesystem-level failure (e.g. $CTX gone) — re-raise so the watcher's
        # own error handling surfaces it; there is nothing safe left to write.
        raise
PY

    fi   # end if INTEGRATION_ESCALATE

  fi   # end if REQ_CHECKPOINT_TYPE = "integration"

  # ── build the task prompt (names $CTX-relative files only; never log.md) ───
  DELEGATE_TASK_PROMPT="You are reviewing checkpoint ${REQ_CHECKPOINT} as The Delegate. Read these files in your read scope: delegate.md (your role and the critic checklist), conventions.md (house conventions), log-slice.md (this checkpoint's log slice only), state.json (run state), and the artifact under review: ${artifact_base}. Apply the critic checklist in delegate.md and emit a verdict JSON conforming to the schema. Do not look for log.md — it is intentionally out of scope. If the full log.md or a session transcript is present in your read scope, do not review; emit the DELEGATE FLAG and stop."

  # ── override the task prompt for integration checkpoints (BLOCKER 1) ───────
  # Tell the Delegate to read integration-results.json. The routine prompt above is
  # used unchanged when checkpoint-type is routine/absent.
  if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]; then
    DELEGATE_TASK_PROMPT="You are reviewing checkpoint ${REQ_CHECKPOINT} as The Delegate. Read these files in your read scope: delegate.md (your role and the critic checklist), conventions.md (house conventions), log-slice.md (this checkpoint's log slice only), state.json (run state), the artifact under review: ${artifact_base}, and integration-results.json (the watcher-staged canonical gate results — EXPECTED file; do not treat as a coldness-breaking foreign file). Apply the verifying-mode checklist in delegate.md's Verifying mode section and emit a verdict JSON conforming to the schema, including a well-formed Integration-evidence block. Do not look for log.md — it is intentionally out of scope. If the full log.md or a session transcript is present in your read scope, do not review; emit the DELEGATE FLAG and stop."
  fi

  # ── system prompt: names the Delegate identity (belt-and-suspenders w/ --bare)
  DELEGATE_SYSTEM_PROMPT="You are The Delegate. Do not load CLAUDE.md. Do not act as the Conductor."

  DELEGATE_MODEL="$(resolve_delegate_model)"

  out_json="$CHECKPOINTS_DIR/$NN.delegate-out.json"
  err_log="$CHECKPOINTS_DIR/$NN.delegate-err.log"

  # ── spawn the Delegate headless (exact invocation: bridge § 3) ─────────────
  # The ONLY read root is the staged NN-context dir ($CTX) — never the whole run
  # dir. EC8 is a filesystem-level exclusion, not a prompt-level instruction.
  # The --add-dir flag below therefore points at the per-checkpoint context dir.
  claude -p \
    --bare \
    --system-prompt "$DELEGATE_SYSTEM_PROMPT" \
    --model "$DELEGATE_MODEL" \
    --output-format json \
    --json-schema "$ROOT/config/delegate-verdict.schema.json" \
    --tools "Read" \
    --add-dir "$CTX" \
    --setting-sources "" \
    --no-session-persistence \
    --max-budget-usd "$DELEGATE_MAX_USD" \
    "$DELEGATE_TASK_PROMPT" \
    > "$out_json" \
    2> "$err_log"
  # --setting-sources "" — W1-verified: suppresses user/project/local settings.json, not covered by --bare

  # ── on claude exit: validate + write the verdict + append ledger ───────────
  # verdict-write.sh owns every durable write; the Delegate never writes the repo.
  if sh "$SCRIPT_DIR/verdict-write.sh" \
    "$out_json" \
    "$request_file" \
    "$verdict_file" \
    "$RUN_DIR/delegate-decisions.md" \
    "$RUN_DIR" \
    "$REVISION_CAP"
  then
    # Success: a verdict was written. Clear any prior failcount for this NN.
    rm -f "$failcount_file"
  else
    # Failure: no verdict written. Bound total spend by counting consecutive
    # spawn failures per NN (W1). --max-budget-usd caps each spawn but NOT the
    # count, so without this the loop would re-spawn `claude` every poll forever.
    echo "watcher: verdict-write.sh reported a validation failure for $NN (held; no verdict written)" >&2
    failcount=0
    [ -f "$failcount_file" ] && failcount="$(cat "$failcount_file" 2>/dev/null)"
    case "$failcount" in *[!0-9]* | '') failcount=0 ;; esac
    failcount=$((failcount + 1))
    printf '%s' "$failcount" > "$failcount_file"

    if [ "$failcount" -ge "$MAX_SPAWN_FAILURES" ]; then
      # Ceiling hit: stop re-spawning this request. Escalate, poison-mark it so
      # later poll passes skip it, drop the failcount, and move on.
      echo "watcher: delegate spawn failed $failcount times for $NN — giving up (attended intervention needed)" >&2
      sh "$SCRIPT_DIR/notify-escalation.sh" "$NN" "$RUN_DIR" \
        "delegate spawn failed $MAX_SPAWN_FAILURES times for checkpoint $NN — giving up, attended intervention needed" \
        || true
      : > "$failed_marker"
      rm -f "$failcount_file"
    fi
  fi

  # ── teardown: drop the throwaway context dir and release the lock ──────────
  rm -rf "$CTX"
  rm -rf "$lock_dir"
}

# ── main ─────────────────────────────────────────────────────────────────────

mkdir -p "$CHECKPOINTS_DIR"
reclaim_stale_locks

echo "watcher: polling $CHECKPOINTS_DIR (interval ${POLL_INTERVAL}s, cap ${REVISION_CAP}, max \$${DELEGATE_MAX_USD}/checkpoint)" >&2

while [ "$watcher_running" -eq 1 ]; do
  for request_file in "$CHECKPOINTS_DIR"/*-request.md; do
    [ -f "$request_file" ] || continue
    process_request "$request_file"
  done
  sleep "$POLL_INTERVAL"
done

exit 0
