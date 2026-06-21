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

  # Skip a request that already has a verdict (FR 38). The 'verdict.md' token
  # here is also the static guard fixture 05 greps for.
  if [ -f "$verdict_file" ]; then
    return 0
  fi

  # If a lock already exists, honour it unless its PID is dead (crashed watcher).
  if [ -d "$lock_dir" ]; then
    lock_pid=""
    [ -f "$lock_dir/pid" ] && lock_pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    if pid_alive "$lock_pid"; then
      return 0
    fi
    echo "watcher: clearing dead lock (pid '${lock_pid:-none}') for $NN" >&2
    rm -rf "$lock_dir"
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
  if [ -z "$REQ_LOG_SLICE" ] || [ ! -f "$REQ_LOG_SLICE" ]; then
    echo "watcher: request $NN log-slice missing or unreadable: '$REQ_LOG_SLICE' — releasing" >&2
    rm -rf "$lock_dir"
    return 0
  fi

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

  # ── build the task prompt (names $CTX-relative files only; never log.md) ───
  DELEGATE_TASK_PROMPT="You are reviewing checkpoint ${REQ_CHECKPOINT} as The Delegate. Read these files in your read scope: delegate.md (your role and the critic checklist), conventions.md (house conventions), log-slice.md (this checkpoint's log slice only), state.json (run state), and the artifact under review: ${artifact_base}. Apply the critic checklist in delegate.md and emit a verdict JSON conforming to the schema. Do not look for log.md — it is intentionally out of scope. If the full log.md or a session transcript is present in your read scope, do not review; emit the DELEGATE FLAG and stop."

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
  sh "$SCRIPT_DIR/verdict-write.sh" \
    "$out_json" \
    "$request_file" \
    "$verdict_file" \
    "$RUN_DIR/delegate-decisions.md" \
    "$RUN_DIR" \
    "$REVISION_CAP" \
    || echo "watcher: verdict-write.sh reported a validation failure for $NN (held; no verdict written)" >&2

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
