#!/usr/bin/env bash
# conductor-stop.sh — Claude Code Stop hook (Bundle 11, Phase 3).
#
# Fires once per main-session response and once after the session ends.
# Captures the Conductor's own token usage from the main transcript,
# manages the FR 6 pointer file lifecycle, and performs a one-shot
# final capture with self-refresh on the first post-closure fire.
#
# CRITICAL: This hook fires for EVERY Claude Code main session on this
# machine. Non-bureau sessions exit 0 silently via the fail-safe ladder.
# A crash or non-zero exit here would disrupt unrelated work — all
# own-errors log to stderr and exit 0.
#
# Fail-safe ladder (checked in order; first miss → exit 0 silently):
#   A   stop_hook_active guard — prevents hook re-entry loops
#   A.5 resolve pointer path (BUREAU_POINTER_FILE or default)
#   B   pointer file present and valid JSON with three required keys
#   C   both NONCE and RUN_DIR present in transcript file content
#   D   RUN_DIR exists as a directory AND RUN_DIR/log.md is readable
#
# Portability: Bash 3.2 + jq on macOS. No set -e (hooks must always
# exit 0); errors are logged to stderr. No associative arrays, no
# GNU-only date flags.
#
# Field names confirmed in docs/run-accounting.md § "Hook field names
# (Bundle 11 ground truth)": transcript_path, session_id, stop_hook_active.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Step A: Loop guard ───────────────────────────────────────────────────────
# If stop_hook_active is true the hook is already running for this session
# event. Exit 0 immediately to prevent a hook re-entry loop.
stdin_json=$(cat)
stop_hook_active=$(printf '%s' "$stdin_json" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

# ── Step A.5: Resolve pointer path ──────────────────────────────────────────
# Specified once here; used for ALL pointer reads, existence checks, and the
# compare-before-rm removal in Step G(3). Tests set BUREAU_POINTER_FILE to a
# path inside a temp dir so no fixture touches the real ~/.novadiem directory.
POINTER_FILE="${BUREAU_POINTER_FILE:-$HOME/.novadiem/bureau-active-run}"

# ── Step B: Read and validate the pointer file ──────────────────────────────
# The pointer file is one-line JSON:
#   {"run_dir":"<abs path>","nonce":"<token>","written_at":"<ISO-8601>"}
if [ ! -e "$POINTER_FILE" ]; then
  exit 0  # No active bureau run — silent no-op
fi

pointer_json=$(cat "$POINTER_FILE" 2>/dev/null)
if [ -z "$pointer_json" ]; then
  echo "[conductor-stop] pointer file unreadable or empty: $POINTER_FILE" >&2
  exit 0
fi

RUN_DIR=$(printf '%s' "$pointer_json" | jq -r '.run_dir // empty' 2>/dev/null)
NONCE=$(printf '%s' "$pointer_json" | jq -r '.nonce // empty' 2>/dev/null)
written_at=$(printf '%s' "$pointer_json" | jq -r '.written_at // empty' 2>/dev/null)

if [ -z "$RUN_DIR" ] || [ -z "$NONCE" ] || [ -z "$written_at" ]; then
  echo "[conductor-stop] pointer file missing required keys (run_dir/nonce/written_at): $POINTER_FILE" >&2
  exit 0
fi

# ── Step C: Ownership check (content-grep on transcript file) ───────────────
# The transcript path is the confirmed field name from docs/run-accounting.md.
# The transcript file lives at a munged-cwd path like:
#   ~/.claude/projects/-Users-robin-Code-novadiem-bureau/<session-id>.jsonl
# This path NEVER contains RUN_DIR or NONCE — a path-based check would always
# fail and silently drop all conductor records. The check must grep FILE CONTENT.
#
# Check 1: nonce must be present in transcript content.
# Check 2: RUN_DIR must be present in transcript content.
# If EITHER fails → exit 0. This closes EC 14: an eval/inspection session
# whose transcript contains RUN_DIR but NOT the nonce exits 0 here.
transcript_path=$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$transcript_path" ] || [ ! -r "$transcript_path" ]; then
  exit 0  # No readable transcript — silent no-op
fi

if ! grep -qF -- "$NONCE" "$transcript_path" 2>/dev/null; then
  exit 0
fi
if ! grep -qF -- "$RUN_DIR" "$transcript_path" 2>/dev/null; then
  exit 0
fi

# ── Step D: Verify RUN_DIR is usable ────────────────────────────────────────
if [ ! -d "$RUN_DIR" ] || [ ! -r "$RUN_DIR/log.md" ]; then
  exit 0  # Run archived or cleaned up — silent no-op
fi

# ── Step E: Sum transcript usage and read closure evidence ───────────────────
# shellcheck source=lib/bureau-token-lib.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bureau-token-lib.sh"

usage_json=$(sum_transcript_usage "$transcript_path" 2>/dev/null) || usage_json=""
if [ -z "$usage_json" ]; then
  usage_json='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}'
  echo "[conductor-stop] WARNING: sum_transcript_usage returned empty for $transcript_path — emitting zero-token event" >&2
fi

# Confirmed field name: session_id (docs/run-accounting.md ground truth)
session_id=$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""
if [ -z "$session_id" ]; then
  session_id="unknown"
fi

# Read closure evidence: parse state.json for accounting.status.
# Fail-safe: missing/unreadable/unparseable state.json → treat as OPEN (never
# false-positive on closure — a false-positive would trigger pointer removal
# before the run is actually closed).
final="false"
if [ -r "$RUN_DIR/state.json" ]; then
  accounting_status=$(jq -r '.accounting.status // empty' "$RUN_DIR/state.json" 2>/dev/null) || accounting_status=""
  # CLOSED when accounting.status is present AND not "pending"
  if [ -n "$accounting_status" ] && [ "$accounting_status" != "pending" ]; then
    final="true"
  fi
fi

# ── Step F: Append CONDUCTOR-TOKEN-EVENT ─────────────────────────────────────
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

event_line=$(printf '%s' "$usage_json" | jq -c \
  --arg session_id "$session_id" \
  --arg at "$now" \
  --argjson final "$final" \
  '{
    session_id: $session_id,
    at: $at,
    turns: .turns,
    tokens: {
      input: .input,
      cache_creation: .cache_creation,
      cache_read: .cache_read,
      processed: .processed,
      output: .output
    },
    final: $final
  }' 2>/dev/null) || event_line=""

if [ -z "$event_line" ]; then
  echo "[conductor-stop] WARNING: failed to compose event JSON — skipping append" >&2
  exit 0
fi

locked_append "$RUN_DIR/log.md" "CONDUCTOR-TOKEN-EVENT: $event_line"

# If the run is still open, nothing more to do — pointer stays in place.
if [ "$final" = "false" ]; then
  exit 0
fi

# ── Step G: One-shot final capture (final=true ONLY) ─────────────────────────
# THE ORDER IS MANDATORY AND LOAD-BEARING. Do not reorder these three steps.
#
# (1) CONDUCTOR-TOKEN-EVENT with final:true was already appended in Step F.
#     Do not append again.
#
# (2) Best-effort self-refresh: re-run account-run.sh to rewrite accounting.json
#     to "exact" from the now-complete log.md.
#     Stdout is suppressed: the Claude Code harness JSON-parses exit-0 hook
#     stdout; any non-JSON text produces undefined harness behavior, so the
#     hook's stdout channel must stay clean. The call is best-effort — wrap
#     in a safe conditional and log failure to stderr only.
if "$SCRIPT_DIR/account-run.sh" "$RUN_DIR" >/dev/null 2>/dev/null; then
  :
else
  echo "[conductor-stop] self-refresh failed — accounting.json stays partial" >&2
fi

# (3) Compare-before-rm: remove the pointer ONLY if it still names this run's
#     run_dir AND nonce. Re-read to detect the case where a newer run has
#     already enrolled (overwritten the pointer with its own nonce/path).
if [ ! -e "$POINTER_FILE" ]; then
  exit 0  # Already removed — nothing to do
fi
current_run_dir=$(jq -r '.run_dir // empty' "$POINTER_FILE" 2>/dev/null) || current_run_dir=""
current_nonce=$(jq -r '.nonce // empty' "$POINTER_FILE" 2>/dev/null) || current_nonce=""
if [ "$current_run_dir" = "$RUN_DIR" ] && [ "$current_nonce" = "$NONCE" ]; then
  rm "$POINTER_FILE" 2>/dev/null || true
fi
# If either differs, leave the pointer untouched — a newer run has enrolled.

exit 0
