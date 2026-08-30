#!/usr/bin/env bash
# run-grok-specialist.sh — sketched Grok host transport for a Bureau specialist.
#
# Usage:
#   run-grok-specialist.sh [--plan] <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>
#
# This is the spawn *audit* helper for runtime=grok. Live launch is the Grok Bot
# Task executor (GROK.md). Bash cannot spawn those Tasks, so this script never
# executes a model, never CreateAgent-fleets, and never resumes a named teammate.
#
# --plan prints the intended spawn payload as JSON and exits 2 with
# GROK-TRANSPORT-UNAVAILABLE. The Delegate/Conductor logs that payload, then
# issues the Task. Without --plan it still only validates.
#
# Claude Code and Codex paths do not call this script.

set -u
umask 077

PLAN=0
if [ "${1:-}" = "--plan" ]; then
  PLAN=1
  shift
fi

if [ "$#" -ne 4 ]; then
  echo "run-grok-specialist: usage: [--plan] <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>" >&2
  exit 2
fi

RUN_DIR="$1"
ROLE="$2"
PROMPT_FILE="$3"
ATTEMPT_ID="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING="$RUN_DIR/model-routing.json"
STATE="$RUN_DIR/state.json"

fail() {
  echo "run-grok-specialist: $*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

case "$ROLE" in
  conductor|challenger|architect|mage|analyst|cleric|spellwright|counselor|scribe|systemsmith|mechanic|witness|tally|scoot|coupler|notary|delegate) ;;
  *) fail "unknown Bureau role: $ROLE" ;;
esac

if [[ ! "$ATTEMPT_ID" =~ ^[a-z]+-[1-9][0-9]*$ ]]; then
  fail "attempt id must be <role>-<positive integer>: $ATTEMPT_ID"
fi
[[ "$ATTEMPT_ID" == "$ROLE"-* ]] || fail "attempt id $ATTEMPT_ID does not match role $ROLE"

[ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
[ -f "$PROMPT_FILE" ] || fail "prompt file does not exist: $PROMPT_FILE"
[ ! -L "$PROMPT_FILE" ] || fail "prompt file must not be a symlink"
[ -s "$ROUTING" ] || fail "model-routing.json is absent or empty"

RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || fail "cannot resolve RUN_DIR"
PROMPT_DIR="$(cd "$(dirname "$PROMPT_FILE")" && pwd -P)" || fail "cannot resolve prompt directory"
PROMPT_FILE="$PROMPT_DIR/$(basename "$PROMPT_FILE")"
ROUTING="$RUN_DIR/model-routing.json"
STATE="$RUN_DIR/state.json"

RUNTIME="$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)"
[ "$RUNTIME" = "grok" ] || fail "Grok transport requires model-routing.json#runtime=grok (got '${RUNTIME:-empty}'). Claude/Codex runs must not call this helper."

MODEL="$(jq -r --arg role "$ROLE" '.roles[$role].model // empty' "$ROUTING" 2>/dev/null)"
TIER="$(jq -r --arg role "$ROLE" '.roles[$role].tier // empty' "$ROUTING" 2>/dev/null)"
EFFORT="$(jq -r --arg role "$ROLE" '.roles[$role].reasoningEffort // .roles[$role].reasoning_effort // empty' "$ROUTING" 2>/dev/null)"
FRESH="$(jq -r --arg role "$ROLE" '.roles[$role].freshContextRequired // .roles[$role].fresh_context_required // false' "$ROUTING" 2>/dev/null)"

[ -n "$MODEL" ] || fail "no resolved model for role $ROLE"
case "$MODEL" in
  grok-4.3|grok-4.6) ;;
  grok-build-0.1) fail "grok-build-0.1 is exec-profile only; this helper is native spawn, not Build" ;;
  *) fail "resolved model is not in Grok spawn allowlist: $MODEL" ;;
esac

# Isolation contract (must all hold before this helper may ever exec a model).
# Standing Grok Bot agents, group rooms, and CreateAgent fleets are forbidden:
# they retain memory and parent chat, which defeats cold review.
isolation_ok=0
isolation_reason="no host has proven a blank specialist context (no parent transcript, no durable agent memory, no CreateAgent fleet)"

payload="$(jq -n \
  --arg runDir "$RUN_DIR" \
  --arg role "$ROLE" \
  --arg attemptId "$ATTEMPT_ID" \
  --arg promptFile "$PROMPT_FILE" \
  --arg model "$MODEL" \
  --arg tier "$TIER" \
  --arg reasoningEffort "$EFFORT" \
  --argjson freshContextRequired "$([ "$FRESH" = "true" ] && echo true || echo false)" \
  --arg isolationReason "$isolation_reason" \
  '{
    transport: "grok-specialist-fail-closed",
    status: "unavailable",
    runtime: "grok",
    fork_context: false,
    inherit_parent_transcript: false,
    standing_agent_forbidden: true,
    runDir: $runDir,
    role: $role,
    attemptId: $attemptId,
    promptFile: $promptFile,
    model: $model,
    tier: $tier,
    reasoningEffort: $reasoningEffort,
    freshContextRequired: $freshContextRequired,
    handoff: "on-disk RUN_DIR artifacts only; chat prose is not the handoff",
    isolation: {
      ok: false,
      reason: $isolationReason
    }
  }')"

if [ "$PLAN" -eq 1 ]; then
  printf '%s\n' "$payload"
fi

echo "GROK-TRANSPORT-UNAVAILABLE: $isolation_reason" >&2
echo "GROK-TRANSPORT-UNAVAILABLE: spawn not executed (role=$ROLE attempt=$ATTEMPT_ID model=$MODEL). run-start.sh still refuses --runtime grok. Claude/Codex unaffected." >&2
exit 2
