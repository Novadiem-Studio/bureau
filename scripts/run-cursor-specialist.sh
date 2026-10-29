#!/usr/bin/env bash
# run-cursor-specialist.sh — spawn helper for runtime=cursor.
#
# Usage:
#   run-cursor-specialist.sh [--plan|--launch] [--environment local|cloud] \
#     [--workspace PATH] <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>
#
# Local (default) and same-workspace cloud: live launch is the Cursor Agent
# Task tool. Bash cannot spawn those Tasks, so --plan prints the payload and
# exits 2 with CURSOR-TRANSPORT-HOST-TASK-REQUIRED. The Delegate/Conductor
# then issues the Task.
#
# Multi-repo cloud (Bureau install session + a different target): Task
# environment:cloud would clone the Bureau, not the target. --plan prints a
# Cloud Agents API payload (repos[] = target only) and exits 2 with
# CURSOR-TRANSPORT-CLOUD-API-REQUIRED. --launch POSTs that payload when
# CURSOR_API_KEY is set. Never vendors the Bureau onto the VM. Never opens
# a Cursor-owned PR (Bureau owns delivery). Never writes .cursor/agents desks.
#
# Claude Code, Codex, and Grok Bot paths do not call this script.

set -u
umask 077

PLAN=0
LAUNCH=0
ENVIRONMENT="local"
WORKSPACE="${CURSOR_WORKSPACE:-}"
while [ "${1:-}" = "--plan" ] || [ "${1:-}" = "--launch" ] \
  || [ "${1:-}" = "--environment" ] || [ "${1:-}" = "--workspace" ]; do
  if [ "${1:-}" = "--plan" ]; then
    PLAN=1
    shift
    continue
  fi
  if [ "${1:-}" = "--launch" ]; then
    LAUNCH=1
    shift
    continue
  fi
  [ "$#" -ge 2 ] || {
    echo "run-cursor-specialist: missing argument: $1" >&2
    exit 2
  }
  if [ "${1:-}" = "--environment" ]; then
    ENVIRONMENT="$2"
  else
    WORKSPACE="$2"
  fi
  shift 2
done

if [ "$PLAN" -eq 1 ] && [ "$LAUNCH" -eq 1 ]; then
  echo "run-cursor-specialist: use --plan or --launch, not both" >&2
  exit 2
fi

if [ "$#" -ne 4 ]; then
  echo "run-cursor-specialist: usage: [--plan|--launch] [--environment local|cloud] [--workspace PATH] <RUN_DIR> <ROLE> <PROMPT_FILE> <ATTEMPT_ID>" >&2
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

CLOUD_TARGET='{"mode":"local","repos":[]}'
if [ "$ENVIRONMENT" = "cloud" ]; then
  TARGET_ARGS=()
  [ -n "$WORKSPACE" ] && TARGET_ARGS=(--workspace "$WORKSPACE")
  CLOUD_TARGET="$("$SCRIPT_DIR/cursor-cloud-target.sh" "${TARGET_ARGS[@]}" "$RUN_DIR")" \
    || fail "cloud target resolution failed"
  CLOUD_MODE="$(printf '%s' "$CLOUD_TARGET" | jq -r '.mode')"
  if [ "$ROLE" = "conductor" ] && [ "$CLOUD_MODE" = "cloud-api-target" ]; then
    fail "Conductor stays in the manager workspace so it can spawn; only producers go to a target-only cloud VM"
  fi
fi

TRANSPORT="cursor-task"
STATUS="host-task-required"
HOST_LINE="CURSOR-TRANSPORT-HOST-TASK-REQUIRED: spawn not executed (role=$ROLE attempt=$ATTEMPT_ID model=$MODEL environment=$ENVIRONMENT). Issue a blank Cursor Task with this payload; do not inherit the manager model."
if [ "$ENVIRONMENT" = "cloud" ] && [ "$(printf '%s' "$CLOUD_TARGET" | jq -r '.mode')" = "cloud-api-target" ]; then
  TRANSPORT="cursor-cloud-api"
  STATUS="host-cloud-api-required"
  HOST_LINE="CURSOR-TRANSPORT-CLOUD-API-REQUIRED: spawn not executed (role=$ROLE attempt=$ATTEMPT_ID model=$MODEL). Task environment:cloud would clone this workspace, not the target. POST /v1/agents with payload.cloudRequest (target repo only; do not vendor the Bureau). --launch does that when CURSOR_API_KEY is set."
fi

payload="$(jq -n \
  --arg runDir "$RUN_DIR" \
  --arg role "$ROLE" \
  --arg attemptId "$ATTEMPT_ID" \
  --arg promptFile "$PROMPT_FILE" \
  --arg model "$MODEL" \
  --arg tier "$TIER" \
  --arg reasoningEffort "$EFFORT" \
  --arg environment "$ENVIRONMENT" \
  --arg transport "$TRANSPORT" \
  --arg status "$STATUS" \
  --argjson freshContextRequired "$([ "$FRESH" = "true" ] && echo true || echo false)" \
  --argjson cloud "$CLOUD_TARGET" \
  '{
    transport: $transport,
    status: $status,
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
    handoff: "on-disk RUN_DIR artifacts; if the specialist cannot write RUN_DIR, return an ARTIFACT PACKET",
    isolation: {
      ok: true,
      reason: "fresh Cursor Task or a new Cloud Agents API agent: no parent transcript, no .cursor/agents memory"
    },
    cloud: ($cloud + {
      allowed: ($environment == "cloud"),
      do_not_vendor_bureau: true
    })
  }')"

if [ "$TRANSPORT" = "cursor-cloud-api" ]; then
  PROMPT_TEXT="$(cat "$PROMPT_FILE")"
  CLOUD_REQUEST="$(jq -n \
    --arg text "$PROMPT_TEXT" \
    --arg model "$MODEL" \
    --arg name "bureau-$ROLE-$ATTEMPT_ID" \
    --argjson cloud "$CLOUD_TARGET" \
    '{
      prompt: {text: $text},
      model: {id: $model},
      name: $name,
      repos: $cloud.repos,
      autoCreatePR: false,
      workOnCurrentBranch: $cloud.workOnCurrentBranch,
      metadata: {bureau_role: $name}
    }')"
  payload="$(jq --argjson req "$CLOUD_REQUEST" '.cloudRequest = $req' <<<"$payload")"
fi

if [ "$LAUNCH" -eq 1 ]; then
  [ "$TRANSPORT" = "cursor-cloud-api" ] \
    || fail "--launch is only for multi-repo cloud (Bureau session + a different target); same-workspace cloud uses Task"
  [ -n "${CURSOR_API_KEY:-}" ] \
    || fail "CURSOR_API_KEY is unset; generate one at Cursor Dashboard → API Keys"
  command -v curl >/dev/null 2>&1 || fail "curl is required for --launch"
  LAUNCH_OUT="$(mktemp "${TMPDIR:-/tmp}/cursor-cloud-launch.XXXXXX")" || fail "cannot create temp file"
  HTTP_CODE="$(
    curl -sS -o "$LAUNCH_OUT" -w '%{http_code}' \
      -u "${CURSOR_API_KEY}:" \
      --header 'Content-Type: application/json' \
      --url https://api.cursor.com/v1/agents \
      --data "$(printf '%s' "$payload" | jq -c '.cloudRequest')"
  )" || {
    rm -f "$LAUNCH_OUT"
    fail "Cloud Agents API request failed"
  }
  if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    err="$(cat "$LAUNCH_OUT")"
    rm -f "$LAUNCH_OUT"
    fail "Cloud Agents API HTTP $HTTP_CODE: $err"
  fi
  jq --argjson http "$HTTP_CODE" \
    '.status = "launched" | .httpStatus = ($http|tonumber)' \
    "$LAUNCH_OUT"
  rm -f "$LAUNCH_OUT"
  exit 0
fi

if [ "$PLAN" -eq 1 ]; then
  printf '%s\n' "$payload"
fi

echo "$HOST_LINE" >&2
exit 2
