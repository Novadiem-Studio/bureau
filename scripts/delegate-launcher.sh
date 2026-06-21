#!/bin/sh
# delegate-launcher.sh — process-lifecycle entry point for a delegated run.
#
# Starts the watcher (background poll loop) and, where the host CLI supports it,
# a Conductor session (non-headless). Writes the session record, then waits for
# the watcher to exit or for a teardown signal.
#
# HOST-DEPENDENT CONDUCTOR SESSION START (Notary F8):
#   The true end-to-end — a real Conductor session that reads and acts on the
#   delegate brief — is host-dependent. The script always writes the brief to
#   $RUN_DIR/delegate-brief.md so the Conductor can be pointed at it directly.
#   If the host CLI cannot open a non-interactive Conductor session, the script
#   records conductor_pid=0 and conductor_session_id="" and continues. This is
#   the DOCUMENTED FALLBACK, not a failure.
#   AN ATTENDED FIRST-RUN (human present) is required to validate the full
#   Conductor session start; this script's smoke test does NOT cover that path.
#
# Usage:
#   delegate-launcher.sh <RUN_DIR> [task-brief] [--revision-cap N] [--max-usd F]
#
# Arguments:
#   $1              absolute path to the run dir (must contain state.json)
#   $2              task brief text (optional positional; may be omitted if only
#                   flags are needed, but then the brief defaults to empty)
#   --revision-cap N  override the revision cap (default 2)
#   --max-usd F       override the per-checkpoint spend ceiling (default 0.50)
#
# Environment set / exported:
#   RUN_DIR           absolute path to the run dir
#   ROOT              absolute path to the agent-framework root
#   REVISION_CAP      revision cap integer (default 2, overridable)
#   DELEGATE_MAX_USD  per-checkpoint spend ceiling (default 0.50, overridable)
#
# Exit codes:
#   0   clean exit (watcher exited normally or SIGTERM received)
#   1   bad arguments (RUN_DIR missing or state.json absent)
#
# Spec refs: AC 11, FR 41, FR 42; docs/delegate-bridge.md § 5 (Conductor shim).

# ── parse arguments ──────────────────────────────────────────────────────────

# Defaults
revision_cap=2
max_usd="0.50"
task_brief=""
run_dir_arg=""
brief_parsed=0

# $1 must be the RUN_DIR (positional, required).
if [ "$#" -eq 0 ]; then
  echo "Usage: delegate-launcher.sh <RUN_DIR> [task-brief] [--revision-cap N] [--max-usd F]" >&2
  exit 1
fi

run_dir_arg="$1"
shift

# Remaining args: optional task brief (first non-flag arg) + flags.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --revision-cap)
      shift
      case "$1" in
        '' | *[!0-9]*)
          echo "delegate-launcher: --revision-cap requires a positive integer, got: '$1'" >&2
          exit 1
          ;;
      esac
      revision_cap="$1"
      shift
      ;;
    --max-usd)
      shift
      case "$1" in
        '' | *[!0-9.]* | *.*.*)
          echo "delegate-launcher: --max-usd requires a non-negative number (e.g. 0.50), got: '$1'" >&2
          exit 1
          ;;
      esac
      max_usd="$1"
      shift
      ;;
    --)
      shift
      # Everything after -- is the task brief.
      task_brief="$*"
      break
      ;;
    -*)
      echo "delegate-launcher: unknown flag: $1" >&2
      exit 1
      ;;
    *)
      # First non-flag positional is the task brief (only capture once).
      if [ "$brief_parsed" -eq 0 ]; then
        task_brief="$1"
        brief_parsed=1
      fi
      shift
      ;;
  esac
done

# ── validate RUN_DIR ─────────────────────────────────────────────────────────

if [ -z "$run_dir_arg" ] || [ ! -d "$run_dir_arg" ]; then
  echo "delegate-launcher: RUN_DIR does not exist or is not a directory: '$run_dir_arg'" >&2
  exit 1
fi

if [ ! -f "$run_dir_arg/state.json" ]; then
  echo "delegate-launcher: state.json not found in RUN_DIR: $run_dir_arg" >&2
  exit 1
fi

# ── set and export environment ───────────────────────────────────────────────

export RUN_DIR="$run_dir_arg"
# ROOT: derived from this script's own location (scripts/ -> parent = framework root)
# so the launcher always drives the same checkout it lives in. Override by pre-setting
# ROOT in the environment (e.g. for smoke tests against a specific worktree).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ROOT="${ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export REVISION_CAP="$revision_cap"
export DELEGATE_MAX_USD="$max_usd"

# ── create checkpoints dir ───────────────────────────────────────────────────

mkdir -p "$RUN_DIR/checkpoints"

# ── start watcher in background ──────────────────────────────────────────────

"$ROOT/scripts/watcher.sh" "$RUN_DIR" &
WATCHER_PID=$!
# W3: arm teardown immediately so no signal between here and the later `trap` line
# can orphan the watcher. The teardown function is defined below; the trap references
# it by name, which is resolved at signal-delivery time (POSIX sh defers lookup).
trap teardown TERM INT
echo "delegate-launcher: watcher started (pid $WATCHER_PID)" >&2

# ── write the Conductor brief to disk (Notary F8) ────────────────────────────
# The brief is always written to $RUN_DIR/delegate-brief.md regardless of
# whether the host CLI can open a Conductor session. If the CLI session-start
# mechanism does not accept inline text, point the Conductor at this file.

cat > "$RUN_DIR/delegate-brief.md" <<BRIEF
Read agent-framework/CLAUDE.md and agent-framework/docs/delegate-bridge.md. You are
running a delegated session. The Delegate watcher is active at RUN_DIR/checkpoints/.
Use the "Consuming a delegate verdict" shim at every checkpoint (see orchestrator.md).
RUN_DIR: $RUN_DIR
Task: $task_brief
BRIEF

echo "delegate-launcher: brief written to $RUN_DIR/delegate-brief.md" >&2

# ── start Conductor session (host-dependent) ──────────────────────────────────
# Whether the host CLI supports launching a non-interactive Conductor session
# varies. This block attempts a best-effort launch; on failure, it falls back to
# conductor_pid=0 / conductor_session_id="" without aborting. The attended
# first-run must verify the Conductor session path end-to-end.
#
# Note: `claude` in non-print mode opens an interactive TUI which cannot be
# driven unattended from a shell script without PTY allocation (not POSIX-safe).
# The block below therefore does NOT attempt a real `claude` API call — that
# would block or fail in a smoke test / CI environment. Instead it records the
# documented fallback values. An attended operator launches the Conductor manually
# by pointing it at $RUN_DIR/delegate-brief.md.

CONDUCTOR_PID=0
conductor_session_id=""

# For future extensibility: if the host provides a CLI flag for a non-interactive
# session (e.g. `claude --session-id-only` or similar), call it here, capture the
# PID and session ID, and replace the fallback values above. That path is NOT
# implemented in this bundle; the attended-first-run requirement (Notary F8 /
# FR 43) gates it. Do NOT add a real `claude` invocation here without that gate.

echo "delegate-launcher: conductor session start is host-dependent — brief is at $RUN_DIR/delegate-brief.md" >&2
echo "delegate-launcher: ATTENDED FIRST-RUN required to validate full Conductor session start" >&2

# ── write delegate-session.json (AC 11) ─────────────────────────────────────

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$RUN_DIR/delegate-session.json" \
          "$CONDUCTOR_PID" "$WATCHER_PID" "$conductor_session_id" \
          "$RUN_DIR" "$started_at" "$REVISION_CAP" "$DELEGATE_MAX_USD" <<'PY'
import json, sys
out_path      = sys.argv[1]
cond_pid      = int(sys.argv[2])
watch_pid     = int(sys.argv[3])
cond_sess     = sys.argv[4]
run_dir       = sys.argv[5]
started_at    = sys.argv[6]
rev_cap       = int(sys.argv[7])
max_usd       = float(sys.argv[8])

record = {
    "conductor_pid":        cond_pid,
    "watcher_pid":          watch_pid,
    "conductor_session_id": cond_sess,
    "run_dir":              run_dir,
    "started_at":           started_at,
    "revision_cap":         rev_cap,
    "delegate_max_usd":     max_usd,
}
with open(out_path, "w") as fh:
    json.dump(record, fh, indent=2)
    fh.write("\n")
PY

# Validate the JSON was written cleanly.
python3 -c "import json; json.load(open('$RUN_DIR/delegate-session.json'))" \
  && echo "delegate-launcher: delegate-session.json written and valid" >&2 \
  || { echo "delegate-launcher: ERROR — delegate-session.json failed JSON validation" >&2; exit 1; }

# ── teardown helpers ─────────────────────────────────────────────────────────
# do_teardown: shared logic called from both the signal trap and the inline
# post-wait path. Never calls exit itself — callers decide the exit path.
# W5: factored out so summary-gen runs at most once regardless of which path
# reaches it first.

do_teardown() {
  # Kill the watcher.
  if [ -n "$WATCHER_PID" ] && kill -0 "$WATCHER_PID" 2>/dev/null; then
    echo "delegate-launcher: killing watcher (pid $WATCHER_PID)" >&2
    kill "$WATCHER_PID" 2>/dev/null || true
  fi

  # Kill the Conductor if it was started as a background process (non-zero PID).
  # W4: guard both non-empty and non-zero before the arithmetic test.
  if [ -n "$CONDUCTOR_PID" ] && [ "$CONDUCTOR_PID" -ne 0 ] && kill -0 "$CONDUCTOR_PID" 2>/dev/null; then
    echo "delegate-launcher: killing conductor (pid $CONDUCTOR_PID)" >&2
    kill "$CONDUCTOR_PID" 2>/dev/null || true
  fi

  # Generate the run-end summary — but only if the ledger file exists (it is
  # created by the first ledger-append.sh call; before any checkpoint completes
  # it will not exist and we exit gracefully without calling summary-gen).
  if [ -f "$RUN_DIR/delegate-decisions.md" ]; then
    echo "delegate-launcher: generating run summary" >&2
    sh "$ROOT/scripts/summary-gen.sh" \
      "$RUN_DIR/delegate-decisions.md" \
      "$RUN_DIR/delegate-summary.md" || true
    echo "Teardown complete. Summary: $RUN_DIR/delegate-summary.md"
  else
    echo "Teardown complete. Summary: $RUN_DIR/delegate-summary.md"
  fi
}

# teardown: signal trap handler. Disarms itself first (W5) so a second signal
# during teardown cannot re-enter and run summary-gen twice.
teardown() {
  trap - TERM INT
  echo "delegate-launcher: teardown signal received" >&2
  do_teardown
  exit 0
}

# (The early trap TERM INT referencing teardown by name was armed above, right
# after WATCHER_PID=$! — that trap is still in effect here and points at this
# function. No second `trap teardown TERM INT` needed.)

# ── wait for watcher ─────────────────────────────────────────────────────────
# Block here until the watcher exits or until SIGTERM/SIGINT fires the teardown
# trap above. The launcher is the parent of the watcher; `wait` is interrupted
# by the trap so POSIX-sh signal delivery is reliable.

wait "$WATCHER_PID"
WATCHER_EXIT=$?

# Watcher exited on its own (normal or abnormal).
echo "delegate-launcher: watcher exited (status $WATCHER_EXIT)" >&2

# Run teardown inline (the trap won't fire if the watcher exited naturally).
# W5: disarm the trap first so a SIGTERM arriving here cannot also invoke
# teardown() and run summary-gen a second time.
trap - TERM INT
do_teardown

exit 0
