#!/usr/bin/env bash
# subagent-stop.sh — Claude Code SubagentStop hook (Bundle 11, Phase 2).
#
# Fires when each Task subagent completes. Reads the subagent's isolated
# transcript, extracts deduped token usage, and appends one
# SPAWN-TOKEN-EVENT: line to the active bureau run's log.md.
#
# CRITICAL: This hook fires for EVERY Claude Code session on this machine,
# including non-bureau subagents. Non-bureau sessions exit 0 silently via
# the fail-safe ladder below. A crash or non-zero exit here would disrupt
# unrelated work — all own-errors log to stderr and exit 0.
#
# Fail-safe ladder (checked in order; first failure → exit 0):
#   1. agent_transcript_path field present and non-empty
#   2. Transcript file exists and is readable
#   3. First user message contains "RUN_DIR: <path>" (bureau identity check)
#   4. RUN_DIR exists as a directory AND RUN_DIR/log.md is a readable file
#
# Field names confirmed in docs/run-accounting.md § "Hook field names
# (Bundle 11 ground truth)": agent_transcript_path, agent_id.
#
# Portability: Bash 3.2 + jq on macOS. No set -e (hooks must always
# exit 0); errors are logged to stderr. No associative arrays, no GNU-only
# date flags.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helper: read stdin JSON once ────────────────────────────────────────────
stdin_json=$(cat)

# ── Step 1: Extract transcript path ─────────────────────────────────────────
# Confirmed field name: agent_transcript_path (docs/run-accounting.md ground truth)
transcript_path=$(printf '%s' "$stdin_json" | jq -r '.agent_transcript_path // empty' 2>/dev/null)
if [ -z "$transcript_path" ]; then
  exit 0  # Not a subagent with a transcript — silent no-op
fi

# ── Step 2: Verify transcript is readable ───────────────────────────────────
if [ ! -r "$transcript_path" ]; then
  echo "[subagent-stop] transcript not readable: $transcript_path" >&2
  exit 0
fi

# ── Step 3: Extract RUN_DIR from first user message ─────────────────────────
# The first user-role JSONL line is the spawn prompt; bureau spawns always
# include "RUN_DIR: <abs path>" in that prompt.
# Use -Rn + fromjson? to skip malformed lines gracefully.
#
# Real Claude Code transcript schema (Bundle 11 ground truth — confirmed 2026-07-05):
#   {"type":"user","message":{"role":"user","content":"<string or array>"}}
# Top-level .role is absent; the selector must match on .type == "user" and
# read .message.content. The old .role? == "user" selector matched ZERO lines
# in production transcripts (silent no-op blocker — Challenger-verified).
first_user_content=$(jq -Rn '
  [inputs | fromjson?]
  | map(select(.type? == "user"))
  | if length > 0 then .[0].message.content else "" end
' "$transcript_path" 2>/dev/null) || first_user_content='""'

# first_user_content is a JSON value (may be a string, array, or null).
# Normalise to a plain text string.
first_user_text=$(printf '%s' "$first_user_content" | jq -r 'if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end' 2>/dev/null) || first_user_text=""

# Extract the RUN_DIR line value
run_dir=""
if printf '%s' "$first_user_text" | grep -q 'RUN_DIR:'; then
  run_dir=$(printf '%s' "$first_user_text" | grep 'RUN_DIR:' | head -1 | sed 's/.*RUN_DIR:[[:space:]]*//' | tr -d '\r')
fi

if [ -z "$run_dir" ]; then
  exit 0  # Not a bureau subagent — silent no-op
fi

# ── Step 4: Verify RUN_DIR and log.md exist ──────────────────────────────────
if [ ! -d "$run_dir" ] || [ ! -r "$run_dir/log.md" ]; then
  exit 0  # Run archived or cleaned up — silent no-op
fi

# ── Step 5: Extract Attempt ID ──────────────────────────────────────────────
attempt_id_raw=""
if printf '%s' "$first_user_text" | grep -q 'Attempt ID:'; then
  attempt_id_raw=$(printf '%s' "$first_user_text" | grep 'Attempt ID:' | head -1 | sed 's/.*Attempt ID:[[:space:]]*//' | tr -d '\r')
fi

if [ -n "$attempt_id_raw" ]; then
  attempt_note=""
else
  attempt_note="attempt_id absent from spawn prompt — record cannot be paired to a SPAWN-EVENT"
fi

# ── Step 6: Extract agent_id from stdin ─────────────────────────────────────
# Confirmed field name: agent_id (docs/run-accounting.md ground truth)
agent_id=$(printf '%s' "$stdin_json" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
if [ -z "$agent_id" ]; then
  # Fallback: derive from transcript basename (agent-<agent_id>.jsonl)
  basename_val=$(basename "$transcript_path" .jsonl)
  agent_id="${basename_val#agent-}"
fi
if [ -z "$agent_id" ]; then
  agent_id="unknown"
fi

# ── Step 7: Sum transcript usage ─────────────────────────────────────────────
# Source the shared library (line-tolerant: malformed JSONL lines are skipped)
# shellcheck source=lib/bureau-token-lib.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bureau-token-lib.sh"

usage_json=""
usage_json=$(sum_transcript_usage "$transcript_path" 2>/dev/null) || usage_json=""

if [ -z "$usage_json" ]; then
  # sum_transcript_usage returned empty — tokens unavailable (fail-safe)
  # Still emit the event with zero tokens so the record is not silently lost
  usage_json='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}'
  echo "[subagent-stop] WARNING: sum_transcript_usage returned empty for $transcript_path — emitting zero-token event" >&2
fi

# ── Step 8: Compose SPAWN-TOKEN-EVENT line ───────────────────────────────────
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

event_line=""
if [ -n "$attempt_note" ]; then
  # attempt_id is null — include _note
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg agent_id "$agent_id" \
    --arg at "$now" \
    --arg note "$attempt_note" \
    '{
      attempt_id: null,
      _note: $note,
      agent_id: $agent_id,
      at: $at,
      turns: .turns,
      tokens: {
        input: .input,
        cache_creation: .cache_creation,
        cache_read: .cache_read,
        processed: .processed,
        output: .output
      }
    }' 2>/dev/null) || event_line=""
else
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg attempt_id "$attempt_id_raw" \
    --arg agent_id "$agent_id" \
    --arg at "$now" \
    '{
      attempt_id: $attempt_id,
      agent_id: $agent_id,
      at: $at,
      turns: .turns,
      tokens: {
        input: .input,
        cache_creation: .cache_creation,
        cache_read: .cache_read,
        processed: .processed,
        output: .output
      }
    }' 2>/dev/null) || event_line=""
fi

if [ -z "$event_line" ]; then
  echo "[subagent-stop] WARNING: failed to compose event JSON — skipping append" >&2
  exit 0
fi

# ── Step 9: Append to log.md ─────────────────────────────────────────────────
locked_append "$run_dir/log.md" "SPAWN-TOKEN-EVENT: $event_line"

exit 0
