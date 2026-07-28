#!/bin/sh
# The Delegate watcher — the poll loop, locking, staging, and Delegate spawn.
#
# Watches RUN_DIR/checkpoints for NN-request.md files. For each unclaimed request
# it: claims an atomic mkdir lock, stages the per-checkpoint read set into a
# scratch context dir, spawns the Delegate cold reviewer against ONLY that packet,
# and on the Delegate's exit calls verdict-write.sh (validate + cap + atomic write
# + ledger append). It then tears down the context dir and the lock.
#
# Three invariants are gated at review and must not regress:
#   1. Identity isolation (EC1): scripts/run-cold-reviewer.sh suppresses host
#      startup context and gives the reviewer the Delegate identity explicitly.
#   2. Log isolation (EC8): the reviewer reads ONLY the staged context packet.
#      log.md is never copied into $CTX, and after staging we assert it is absent.
#   3. Re-entrancy (EC3): the request is claimed with an atomic `mkdir NN.lock`
#      BEFORE staging. Two poll passes (or two watchers) can never spawn two
#      delegates for one request. A request that already has NN-verdict.md is
#      skipped (FR 38). A lock whose PID is dead is reclaimed on startup.
#
# Environment (set by delegate-launcher.sh):
#   RUN_DIR           absolute path to the run dir (also accepted as $1)
#   ROOT              absolute path to the agent-framework root
#   DELEGATE_MAX_USD  per-checkpoint spend ceiling (default 5.00; headroom, a runaway
#                     backstop not a throttle. On a subscription the dollars are notional;
#                     the cap exists only to stop a stuck spawn, never to throttle a real review.)
#   REVISION_CAP      revision cap integer (default 2)
#
# Usage:
#   watcher.sh [RUN_DIR]
#
# Exit codes:
#   0  clean exit (SIGTERM trapped)
#   1  bad configuration (RUN_DIR / ROOT missing or invalid)
#
# Spec refs: docs/delegate-bridge/watcher-v1.md § Section 3 (spawn invocation),
#            § Section 4 (staging), § Section 7 (bridge failure modes);
#            AC 7, AC 13, AC 14; EC1, EC3, EC8.

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

DELEGATE_MAX_USD="${DELEGATE_MAX_USD:-5.00}"
REVISION_CAP="${REVISION_CAP:-2}"
# Per-checkpoint spawn-failure ceiling (money-safety). --max-budget-usd caps the
# spend of ONE spawn but NOT the number of spawns. If the Delegate persistently
# emits invalid/empty JSON, verdict-write.sh fails closed (no verdict) and the
# poll loop would otherwise re-spawn the selected provider every poll — unbounded
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
  REQ_ATTEMPT="$(req_field 'attempt' "$request_file")"

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

  # ── integration-mode request fields (parsed for the gate + reviewer mode) ─────
  # Additive: only the integration path uses these. The routine path (checkpoint-type
  # routine/absent) leaves every variable at its default and never calls the gate
  # below (FR-B14-10, AC-11). No file is written here. The short-circuit guards
  # ((none)-worktree / unresolvable base-ref) and the whole executor body were
  # extracted to scripts/integration-gate.sh (Bundle 15 P4, FR14 single-source);
  # watcher.sh parses these fields to build that gate's CLI flags and select the
  # helper's integration reviewer mode.
  REQ_CHECKPOINT_TYPE="$(req_field 'checkpoint-type' "$request_file")"
  REQ_WORKTREE_PATH="$(req_field 'worktree-path' "$request_file")"
  REQ_BASE_REF="$(req_field 'base-ref' "$request_file")"
  REQ_CLAIMED_GATES_RAW="$(req_field 'claimed-gates' "$request_file")"
  REQ_KNOWN_FLAKY_RAW="$(req_field 'known-flaky-gates' "$request_file")"

  # ── stage the per-checkpoint read set into NN-context (EC8) ────────────────
  # The staged dir is the Delegate's ONLY read root. log.md is NEVER copied in.
  CTX="$CHECKPOINTS_DIR/${NN}-context"
  rm -rf "$CTX"
  mkdir -p "$CTX"
  cp "$REQ_ARTIFACT"               "$CTX/"
  cp "$REQ_LOG_SLICE"              "$CTX/log-slice.md"
  cp "$RUN_DIR/state.json"         "$CTX/"
  cp "$ROOT/docs/conventions.md"   "$CTX/"
  mkdir -p "$CTX/conventions"
  cp "$ROOT/docs/conventions/"*.md "$CTX/conventions/"
  # Stage ONLY the cold-reviewer-mode SECTION of agents/delegate.md (W-d / W7).
  # The full dual-mode file grants manager-mode Bash/Write/spawn capabilities a
  # read-only reviewer must never read as its own; the awk slice extracts just the
  # COLD-REVIEWER-MODE:BEGIN/END block into delegate-reviewer.md (bridge v2 §4).
  # NOTE: those markers are written into agents/delegate.md by Bundle 15 P5 (Phase
  # 3); until P5 lands this slice is EMPTY — wire it now, the slice fills then.
  awk '/^# COLD-REVIEWER-MODE:BEGIN/,/^# COLD-REVIEWER-MODE:END/' \
    "$ROOT/agents/delegate.md" > "$CTX/delegate-reviewer.md"

  # EC8 assertion: log.md must never be in the staged context dir. If a copy ever
  # included it (e.g. the artifact itself was named log.md, or a future edit
  # widened the staging set), remove it and warn — coldness must not break.
  if [ -e "$CTX/log.md" ]; then
    echo "watcher: WARNING — log.md present in staged context $CTX — removing (EC8 isolation)" >&2
    rm -f "$CTX/log.md"
  fi

  artifact_base="$(basename "$REQ_ARTIFACT")"

  # ── integration-mode gate: the single shared executor (FR14 / OQ1) ─────────
  # The inline integration executor (part A short-circuit guards + part B body)
  # was extracted to scripts/integration-gate.sh in Bundle 15 P4 — one copy, two
  # callers (this watcher + the v2 Delegate), no duplicate to drift (bridge v2 §5).
  # $CTX is staged ABOVE this call, so the $CTX-exists-before-write invariant holds:
  # integration-gate.sh writes integration-results.json INTO the already-staged
  # $CTX, exactly as the inline body did. A routine/absent checkpoint-type is a
  # no-op inside the gate (exit 0, no file); the guard here keeps the routine path
  # from spawning the subprocess at all, preserving v1 behavior.
  if [ "$REQ_CHECKPOINT_TYPE" = "integration" ]; then
    gate_err="$CHECKPOINTS_DIR/$NN.gate-err.log"
    sh "$SCRIPT_DIR/integration-gate.sh" \
      --checkpoint-type   "$REQ_CHECKPOINT_TYPE" \
      --worktree-path     "$REQ_WORKTREE_PATH" \
      --base-ref          "$REQ_BASE_REF" \
      --claimed-gates     "$REQ_CLAIMED_GATES_RAW" \
      --known-flaky-gates "$REQ_KNOWN_FLAKY_RAW" \
      --state-json        "$RUN_DIR/state.json" \
      --out               "$CTX" 2> "$gate_err"
    gate_rc=$?
    if [ "$gate_rc" -ne 0 ]; then
      # #28 — CONSUME the gate exit code. integration-gate.sh fails CLOSED
      # (exit 2, no file written) on a write failure (fixture 154). Spawning a
      # reviewer now would review missing/partial evidence, so this is a hard
      # stop for THIS checkpoint: escalate with the gate's own reason (the same
      # notify+poison idiom the spawn-failure ceiling uses at ~411), and RETURN
      # before staging the Delegate spawn. Do NOT bump failcount — that counter
      # bounds retriable reviewer-spawn hiccups (~397-416); a gate fail-closed is
      # not retriable, it is poison-marked once. Over-escalation guard: only a
      # NON-ZERO gate exit reaches here — a routine checkpoint never enters this
      # `if` block (REQ_CHECKPOINT_TYPE guard), and a successful gate (exit 0,
      # file written) proceeds to the normal reviewer/verdict path below.
      gate_reason="$(tail -1 "$gate_err" 2>/dev/null)"
      echo "watcher: integration-gate.sh exited $gate_rc for $NN — escalating, not spawning reviewer" >&2
      sh "$SCRIPT_DIR/notify-escalation.sh" "$NN" "$RUN_DIR" \
        "integration gate failed closed (exit $gate_rc) for checkpoint $NN: ${gate_reason:-no reason captured} — attended intervention needed" \
        || true
      : > "$failed_marker"
      rm -rf "$CTX"
      rm -rf "$lock_dir"
      return
    fi
  fi

  out_json="$CHECKPOINTS_DIR/$NN.delegate-out.json"
  rm -f "$out_json"

  # Use a unique accounting id for every real spawn, including retries of the
  # same request. attempt identifies a re-issued request; the pre-spawn failure
  # count distinguishes transport/validation retries within that attempt.
  prior_failcount=0
  [ -f "$failcount_file" ] && prior_failcount="$(cat "$failcount_file" 2>/dev/null)"
  case "$prior_failcount" in *[!0-9]*|'') prior_failcount=0 ;; esac
  spawn_seq=$((prior_failcount + 1))
  [ -n "$REQ_ATTEMPT" ] || REQ_ATTEMPT=1
  spawn_id="${NN}-${REQ_ATTEMPT}-${spawn_seq}"
  review_mode="routine"
  [ "$REQ_CHECKPOINT_TYPE" = "integration" ] && review_mode="integration"

  # Single provider-neutral entrypoint. It selects Claude or Codex from this
  # run's model-routing.json and returns paths to a normalized verdict and usage
  # envelope. The reviewer never receives a live-run path in its prompt.
  review_meta="$(
    ROOT="$ROOT" \
    DELEGATE_MAX_USD="$DELEGATE_MAX_USD" \
    bash "$SCRIPT_DIR/run-cold-reviewer.sh" \
      "$RUN_DIR" "$CTX" "$REQ_CHECKPOINT" "$spawn_id" "$artifact_base" "$review_mode"
  )"
  review_rc=$?

  if [ "$review_rc" -eq 0 ]; then
    reviewer_verdict="$(printf '%s' "$review_meta" | jq -r '.verdict_path // empty' 2>/dev/null)"
    reviewer_envelope="$(printf '%s' "$review_meta" | jq -r '.envelope_path // empty' 2>/dev/null)"
    if [ -s "$reviewer_verdict" ]; then
      cp "$reviewer_verdict" "$out_json"
    fi
    if [ -s "$reviewer_envelope" ]; then
      envelope_json="$(jq -c '.' "$reviewer_envelope" 2>/dev/null)"
      if [ -n "$envelope_json" ]; then
        bash "$SCRIPT_DIR/append-reviewer-tokens.sh" \
          "$RUN_DIR" "$REQ_CHECKPOINT" "$spawn_id" "$envelope_json" \
          || echo "watcher: token accounting append failed for reviewer spawn $spawn_id" >&2
      fi
    fi
  else
    echo "watcher: cold-reviewer adapter failed for $NN (spawn $spawn_id)" >&2
  fi

  # ── on reviewer exit: validate + write the verdict + append ledger ─────────
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
    # spawn failures per NN (W1). A per-spawn budget guard does not cap the
    # retry count, so without this the loop could re-spawn a provider forever.
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
