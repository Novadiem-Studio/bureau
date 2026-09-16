#!/usr/bin/env bash
# run-cursor-specialist.sh — spawn audit helper for runtime=cursor.
#
# Usage:
#   run-cursor-specialist.sh [--plan] [--environment local|cloud] \
#     <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>
#
# Live launch is the Cursor Agent Task tool (CURSOR.md). Bash cannot spawn
# those Tasks, so this script never executes a model, never writes
# .cursor/agents desks, and never resumes a sticky teammate.
#
# --plan prints the intended spawn payload as JSON and exits 2 with
# CURSOR-TRANSPORT-HOST-TASK-REQUIRED. The Delegate/Conductor logs that
# payload, then issues the Task. Without --plan it still only validates.
#
# Claude Code, Codex, and Grok Bot paths do not call this script.

set -u
umask 077

PLAN=0
ENVIRONMENT="local"
while [ "${1:-}" = "--plan" ] || [ "${1:-}" = "--environment" ]; do
  if [ "${1:-}" = "--plan" ]; then
    PLAN=1
    shift
    continue
  fi
  [ "$#" -ge 2 ] || {
    echo "run-cursor-specialist: missing argument: --environment" >&2
    exit 2
  }
  ENVIRONMENT="$2"
  shift 2
done

if [ "$#" -ne 4 ]; then
  echo "run-cursor-specialist: usage: [--plan] [--environment local|cloud] <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>" >&2
  exit 2
fi

RUN_DIR="$1"
ROLE="$2"
PROMPT_FILE="$3"
ATTEMPT_ID="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING="$RUN_DIR/model-routing.json"

fail() {
  echo "run-cursor-specialist: $*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

case "$ENVIRONMENT" in
  local|cloud) ;;
  *) fail "environment must be local or cloud: $ENVIRONMENT" ;;
esac

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

RUNTIME="$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)"
[ "$RUNTIME" = "cursor" ] || fail "Cursor transport requires model-routing.json#runtime=cursor (got '${RUNTIME:-empty}'). Claude/Codex/Grok runs must not call this helper."

MODEL="$(jq -r --arg role "$ROLE" '.roles[$role].model // empty' "$ROUTING" 2>/dev/null)"
TIER="$(jq -r --arg role "$ROLE" '.roles[$role].tier // empty' "$ROUTING" 2>/dev/null)"
EFFORT="$(jq -r --arg role "$ROLE" '.roles[$role].reasoningEffort // .roles[$role].reasoning_effort // empty' "$ROUTING" 2>/dev/null)"
FRESH="$(jq -r --arg role "$ROLE" '.roles[$role].freshContextRequired // .roles[$role].fresh_context_required // false' "$ROUTING" 2>/dev/null)"

[ -n "$MODEL" ] || fail "no resolved model for role $ROLE"
case "$MODEL" in
  composer-2.5-fast|gpt-5.6-sol-medium|cursor-grok-4.6-high-fast|claude-opus-5-thinking-high) ;;
  inherit) fail "inherit is forbidden; pass the resolved Task slug explicitly" ;;
  *) fail "resolved model is not in Cursor Task spawn allowlist: $MODEL" ;;
esac

case "$ROLE" in
  challenger|notary|delegate)
    if [ "$ENVIRONMENT" = "cloud" ]; then
      fail "cold roles (challenger, notary, delegate-reviewer) stay on local Task; do not send graded review to a cloud VM"
    fi
    ;;
esac

payload="$(jq -n \
  --arg runDir "$RUN_DIR" \
  --arg role "$ROLE" \
  --arg attemptId "$ATTEMPT_ID" \
  --arg promptFile "$PROMPT_FILE" \
  --arg model "$MODEL" \
  --arg tier "$TIER" \
  --arg reasoningEffort "$EFFORT" \
  --arg environment "$ENVIRONMENT" \
  --argjson freshContextRequired "$([ "$FRESH" = "true" ] && echo true || echo false)" \
  '{
    transport: "cursor-task",
    status: "host-task-required",
    runtime: "cursor",
    environment: $environment,
    fork_context: false,
    inherit_parent_transcript: false,
    standing_agent_forbidden: true,
    sticky_cursor_agents_forbidden: true,
    runDir: $runDir,
    role: $role,
    attemptId: $attemptId,
    promptFile: $promptFile,
    model: $model,
    tier: $tier,
    reasoningEffort: $reasoningEffort,
    freshContextRequired: $freshContextRequired,
    handoff: "on-disk RUN_DIR artifacts; if the Task cannot write RUN_DIR, return an ARTIFACT PACKET",
    isolation: {
      ok: true,
      reason: "Cursor Task starts blank: no parent transcript, no .cursor/agents memory"
    },
    cloud: {
      allowed: ($environment == "cloud"),
      workspace_must_be_target_or_bureau_self_run: true,
      do_not_vendor_bureau: true,
      named_gap: "Task cloud clones the current workspace only; multi-repo bureau+target is SDK/API, not this helper"
    }
  }')"

if [ "$PLAN" -eq 1 ]; then
  printf '%s\n' "$payload"
fi

echo "CURSOR-TRANSPORT-HOST-TASK-REQUIRED: spawn not executed (role=$ROLE attempt=$ATTEMPT_ID model=$MODEL environment=$ENVIRONMENT). Issue a blank Cursor Task with this payload; do not inherit the manager model." >&2
exit 2
