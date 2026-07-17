#!/usr/bin/env bash
# run-reopen.sh — Re-open ceremony for a run that continues past a completed close-out.
#
# Use when a bureau run extends past a planning close-out (e.g. a build phase starts
# after the planning-phase accounting was finalized). Without this ceremony, the
# conductor-stop.sh pointer has already been removed, so all subsequent Stop fires
# exit 0 silently — no conductor tokens are captured for the build phase.
#
# What this script does (in order):
#   1. Reset state.json#accounting.status to "pending" so the next Stop fire
#      sees an open run (final="false") and emits per-turn events rather than
#      the one-shot final capture.
#   2. Recover the ORIGINAL baseline: read the last CONDUCTOR-TOKEN-EVENT line in
#      log.md that carries a `baseline` object (non-legacy shape). Writing this
#      baseline into the fresh pointer means subsequent emissions use:
#        delta = cumulative - original_baseline
#      The accounting consumer's max(processed)-per-session_id rule then takes
#      the whole-run delta as the canonical figure, not just the post-reopen slice.
#   3. Write a fresh pointer (new nonce, same RUN_DIR key, with the recovered
#      baseline) and echo it to stdout for transcript enrolment.
#   4. Append a nonce-free log line to RUN_DIR/log.md recording the re-open.
#
# THE BASELINE TRAP: on a same-session re-open, a pointer with baseline:null would
# cause conductor-stop.sh to record a FRESH baseline at the re-open point. The
# accounting consumer's take-max would then keep the OLD (higher) figure from the
# planning phase — losing the build phase tokens. Carrying the ORIGINAL baseline
# forward avoids this: the whole-run delta (cumulative - original) is the correct
# figure and take-max lands on it.
#
# Cross-session safety: if a NEW session fires against a recovered baseline whose
# session_id differs, conductor-stop.sh's EC-4 branch already re-records a fresh
# baseline for the new session — no miscomputation.
#
# Usage:
#   run-reopen.sh <RUN_DIR>
#
# Environment overrides (same as run-start.sh / conductor-stop.sh):
#   BUREAU_POINTER_FILE   force single-file mode at this path (test isolation)
#   BUREAU_POINTER_DIR    override the active-runs directory root (test isolation)
#
# Exit codes:
#   0  ceremony completed; pointer enrolled, state reset, log line appended
#   1  argument error or a required step failed
#
# Bash 3.2 + jq; macOS portable. PATH-pinned for ugrep safety (EC 10).

# Step 0: PATH pin (EC 10 — ugrep guard).
PATH=/usr/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Step 1: Parse + validate arguments ───────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage:
  run-reopen.sh <RUN_DIR>

Re-open a bureau run that has continued past a completed close-out.
Resets accounting.status to "pending" and re-enrolls the conductor pointer
so the next Stop hook fire resumes per-turn token capture.
EOF
  exit 1
}

if [ "$#" -lt 1 ]; then
  echo "run-reopen: missing required argument: <RUN_DIR>" >&2
  usage
fi

RUN_DIR="$1"

case "$RUN_DIR" in
  /*) ;;
  *) echo "run-reopen: RUN_DIR must be an absolute path, got: $RUN_DIR" >&2; usage ;;
esac

if [ ! -d "$RUN_DIR" ]; then
  echo "run-reopen: RUN_DIR does not exist or is not a directory: $RUN_DIR" >&2
  exit 1
fi

STATE_JSON="$RUN_DIR/state.json"
LOG_MD="$RUN_DIR/log.md"

if [ ! -r "$STATE_JSON" ]; then
  echo "run-reopen: state.json not found or not readable: $STATE_JSON" >&2
  exit 1
fi

# ── Step 2: Reset state.json#accounting.status to "pending" ─────────────────
# Atomic temp-then-mv. Tolerate absent accounting.status key (sets it cleanly).
_state_tmp=$(mktemp "$STATE_JSON.tmp.XXXXXX" 2>/dev/null) || {
  echo "run-reopen: mktemp failed for state.json update" >&2
  exit 1
}

if ! jq '.accounting.status = "pending"' "$STATE_JSON" > "$_state_tmp" 2>/dev/null; then
  rm -f "$_state_tmp"
  echo "run-reopen: jq failed to update state.json" >&2
  exit 1
fi

if ! mv "$_state_tmp" "$STATE_JSON"; then
  rm -f "$_state_tmp"
  echo "run-reopen: failed to replace state.json" >&2
  exit 1
fi

# ── Step 3: Recover original baseline from log.md ────────────────────────────
# Read the LAST CONDUCTOR-TOKEN-EVENT line in log.md that carries a `baseline`
# object (non-legacy shape). This is the original subtrahend from the planning
# phase. If no such line exists (legacy run or empty log), use baseline:null —
# which is the correct fresh-enrollment behavior and makes conductor-stop.sh
# record a fresh baseline on the next fire (legacy path, safe).
#
# We scan all CONDUCTOR-TOKEN-EVENT lines in reverse order (tail → head via grep
# + awk), find the last one with a `baseline` object, and extract it verbatim.
recovered_baseline="null"

if [ -r "$LOG_MD" ]; then
  # Collect all CONDUCTOR-TOKEN-EVENT lines, keep only those whose payload has
  # a `baseline` object (not null, not absent). Take the LAST one (tail -1).
  last_baseline_line=$(PATH=/usr/bin:$PATH grep '^CONDUCTOR-TOKEN-EVENT: ' "$LOG_MD" \
    | while IFS= read -r line; do
        payload="${line#CONDUCTOR-TOKEN-EVENT: }"
        bl=$(printf '%s' "$payload" | jq -c 'if (has("baseline")) and ((.baseline | type) == "object") then .baseline else empty end' 2>/dev/null)
        [ -n "$bl" ] && printf '%s\n' "$bl"
      done \
    | tail -1)

  if [ -n "$last_baseline_line" ]; then
    # Validate it is well-formed JSON with the expected numeric fields before using it.
    _bl_ok=$(printf '%s' "$last_baseline_line" | jq -r \
      '[.input, .cache_creation, .cache_read, .processed, .output, .turns]
       | map(numbers) | length == 6' 2>/dev/null) || _bl_ok="false"
    if [ "$_bl_ok" = "true" ]; then
      recovered_baseline="$last_baseline_line"
    else
      echo "run-reopen: last baseline object failed numeric validation — using null (fresh baseline)" >&2
    fi
  fi
  # If no qualifying line found, recovered_baseline stays "null" — correct.
fi

# ── Step 4: Resolve pointer path (same precedence as run-start.sh / conductor-stop.sh) ──
if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  _pointer_file="$BUREAU_POINTER_FILE"
else
  _pointer_dir="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  _ptr_key=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')
  _pointer_file="$_pointer_dir/$_ptr_key"
fi

mkdir -p "$(dirname "$_pointer_file")" || {
  echo "run-reopen: failed to create pointer directory: $(dirname "$_pointer_file")" >&2
  exit 1
}

# ── Step 5: Write fresh pointer with recovered baseline ──────────────────────
# Five-field format: run_dir, nonce, written_at, baseline, project_dir.
# The `baseline` field carries the recovered object (or null for legacy fallback).
# A fresh nonce is generated — this is a new enrollment, not an echo of the prior one.
_new_nonce=$(uuidgen | tr '[:upper:]' '[:lower:]' 2>/dev/null) || {
  echo "run-reopen: uuidgen failed" >&2
  exit 1
}
_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_cwd=$(pwd -P)

if ! printf '%s\n' "$recovered_baseline" | jq -c --arg run_dir "$RUN_DIR" \
  --arg nonce "$_new_nonce" --arg written_at "$_now" --arg project_dir "$_cwd" \
  '{"run_dir": $run_dir, "nonce": $nonce, "written_at": $written_at,
    "baseline": ., "project_dir": $project_dir}' \
  > "$_pointer_file" 2>/dev/null; then
  echo "run-reopen: failed to write pointer file: $_pointer_file" >&2
  exit 1
fi

# FR 2: nonce-echo to stdout — NEVER suppressed, NEVER stderr-only.
# The nonce NEVER appears in log.md or any artifact other than the pointer file
# and the Conductor's transcript.
cat "$_pointer_file"

# ── Step 6: Append nonce-free enrollment log line ────────────────────────────
# Same contract as run-start.sh: a nonce-free line that confirms the re-open
# happened, with a shell-computed timestamp (log-append.sh echoes it for reuse).
bash "$FRAMEWORK_ROOT/scripts/log-append.sh" "$RUN_DIR" \
  "Run re-opened — pointer re-enrolled for build phase; accounting.status reset to pending. Nonce written to pointer file and conductor transcript only. Reading this log does not confer ownership." >/dev/null \
  || { echo "run-reopen: log-append.sh failed for re-open log line" >&2; exit 1; }

exit 0
