#!/usr/bin/env bash
# run-cold-reviewer.sh — provider-neutral cold-reviewer dispatcher.
#
# Usage:
#   run-cold-reviewer.sh <RUN_DIR> <CTX> <checkpoint> <spawn-id> <artifact-basename> <routine|integration>
#
# The caller stages CTX. This script selects the host from model-routing.json
# (`claude` or `openai`/`codex`), runs one fresh reviewer, and writes:
#   checkpoints/<spawn-id>-reviewer-verdict.json
#   checkpoints/<spawn-id>-reviewer-envelope.json
#   checkpoints/<spawn-id>-reviewer-events.jsonl
#   checkpoints/<spawn-id>-reviewer-stderr.log
#
# stdout is one metadata JSON object naming those files. Diagnostics go to
# stderr. The script never appends token events; callers do that exactly once
# after a real spawn by passing reviewer-envelope.json to
# append-reviewer-tokens.sh.

set -u

if [ "$#" -ne 6 ]; then
  echo "run-cold-reviewer: usage: <RUN_DIR> <CTX> <checkpoint> <spawn-id> <artifact-basename> <routine|integration>" >&2
  exit 1
fi

RUN_DIR="$1"
CTX="$2"
CHECKPOINT="$3"
SPAWN_ID="$4"
ARTIFACT_BASE="$5"
REVIEW_MODE="$6"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING="$RUN_DIR/model-routing.json"
SCHEMA="$ROOT/config/delegate-verdict.schema.json"
CODEX_SCHEMA="$ROOT/config/delegate-verdict.codex.schema.json"
CHECKPOINTS_DIR="$RUN_DIR/checkpoints"

fail() {
  echo "run-cold-reviewer: $*" >&2
  exit 1
}

[ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
[ -d "$CTX" ] || fail "CTX is not a directory: $CTX"
[ -f "$SCHEMA" ] || fail "verdict schema not found: $SCHEMA"
[ -f "$CODEX_SCHEMA" ] || fail "Codex verdict schema not found: $CODEX_SCHEMA"

case "$CHECKPOINT" in
  *[!0-9]*|'') fail "checkpoint must contain only digits: $CHECKPOINT" ;;
esac
case "$SPAWN_ID" in
  *[!A-Za-z0-9._-]*|'') fail "spawn-id contains unsafe characters: $SPAWN_ID" ;;
esac
case "$ARTIFACT_BASE" in
  */*|''|.|..) fail "artifact-basename must be one safe basename: $ARTIFACT_BASE" ;;
esac
case "$REVIEW_MODE" in
  routine|integration) ;;
  *) fail "review mode must be routine or integration: $REVIEW_MODE" ;;
esac

CTX="$(cd "$CTX" && pwd -P)" || fail "cannot resolve CTX"
RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || fail "cannot resolve RUN_DIR"
CHECKPOINTS_DIR="$RUN_DIR/checkpoints"
mkdir -p "$CHECKPOINTS_DIR" || fail "cannot create checkpoints directory"

for required in \
  "$CTX/delegate-reviewer.md" \
  "$CTX/conventions.md" \
  "$CTX/log-slice.md" \
  "$CTX/state.json" \
  "$CTX/$ARTIFACT_BASE"
do
  [ -f "$required" ] || fail "staged reviewer file missing: $required"
done
if [ "$REVIEW_MODE" = "integration" ] && [ ! -f "$CTX/integration-results.json" ]; then
  fail "integration review requires staged integration-results.json"
fi

# Symlinks can point through an otherwise-correct staged root. Reject the whole
# packet rather than trying to reason about each target.
if find "$CTX" -type l -print -quit 2>/dev/null | grep -q .; then
  fail "staged context contains a symlink"
fi
if find "$CTX" -type f \( -name 'log.md' -o -iname '*transcript*' \) -print -quit 2>/dev/null | grep -q .; then
  fail "staged context contains a forbidden full-log or transcript-like file"
fi

RUNTIME="${BUREAU_REVIEWER_HOST:-}"
if [ -z "$RUNTIME" ] && [ -f "$ROUTING" ]; then
  RUNTIME="$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)"
fi
[ -n "$RUNTIME" ] || RUNTIME="claude"
case "$RUNTIME" in
  openai|codex) RUNTIME="openai" ;;
  claude) ;;
  *) fail "reviewer host '$RUNTIME' has no cold-reviewer adapter" ;;
esac

MODEL=""
REASONING_EFFORT=""
if [ -f "$ROUTING" ]; then
  MODEL="$(jq -r '.roles.delegate.model // empty' "$ROUTING" 2>/dev/null)"
  REASONING_EFFORT="$(jq -r '.roles.delegate.reasoningEffort // empty' "$ROUTING" 2>/dev/null)"
fi
if [ "$RUNTIME" = "claude" ]; then
  [ -n "$MODEL" ] || MODEL="opus"
else
  [ -n "$MODEL" ] || MODEL="gpt-5.6-sol"
  [ -n "$REASONING_EFFORT" ] || REASONING_EFFORT="high"
fi

VERDICT_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-verdict.json"
ENVELOPE_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-envelope.json"
EVENTS_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-events.jsonl"
STDERR_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-stderr.log"

rm -f "$VERDICT_PATH" "$ENVELOPE_PATH" "$EVENTS_PATH" "$STDERR_PATH"

build_task_prompt() {
  prompt_ctx="$1"
  prompt_artifact="$2"
  if [ "$REVIEW_MODE" = "integration" ]; then
    printf '%s' "You are reviewing checkpoint ${CHECKPOINT} as The Delegate cold reviewer. Read only these staged files: ${prompt_ctx}/delegate-reviewer.md (your role and critic checklist), ${prompt_ctx}/conventions.md (the convention router; load only a needed module from ${prompt_ctx}/conventions/), ${prompt_ctx}/log-slice.md (this checkpoint's slice only), ${prompt_ctx}/state.json (run state), ${prompt_ctx}/${prompt_artifact} (the artifact), and ${prompt_ctx}/integration-results.json (canonical gate results). Apply the verifying-mode checklist and return only a verdict JSON conforming to the supplied schema, including Integration-evidence. Do not look for log.md; it is intentionally unavailable. If a full log or session transcript appears, stop and return an escalate verdict describing the coldness breach."
  else
    printf '%s' "You are reviewing checkpoint ${CHECKPOINT} as The Delegate cold reviewer. Read only these staged files: ${prompt_ctx}/delegate-reviewer.md (your role and critic checklist), ${prompt_ctx}/conventions.md (the convention router; load only a needed module from ${prompt_ctx}/conventions/), ${prompt_ctx}/log-slice.md (this checkpoint's slice only), ${prompt_ctx}/state.json (run state), and ${prompt_ctx}/${prompt_artifact} (the artifact). Apply the critic checklist and return only a verdict JSON conforming to the supplied schema. This is a routine checkpoint, so set Integration-evidence to null when the schema requires that field. Do not look for log.md; it is intentionally unavailable. If a full log or session transcript appears, stop and return an escalate verdict describing the coldness breach."
  fi
}

audit_task_prompt() {
  audit_runtime="$1"
  audit_prompt="$2"
  bash "$SCRIPT_DIR/log-append.sh" "$RUN_DIR" \
    "Cold reviewer prompt — spawn: $SPAWN_ID, runtime: $audit_runtime, prompt: $audit_prompt" \
    >/dev/null \
    || fail "cannot append cold-reviewer prompt audit line"
}

extract_claude_verdict() {
  raw="$1"
  out="$2"
  if jq -e 'type == "object" and has("Decision")' "$raw" >/dev/null 2>&1; then
    jq 'del(.usage, .num_turns, .type, .subtype, .duration_ms, .duration_api_ms, .is_error, .session_id, .total_cost_usd)' \
      "$raw" > "$out"
  elif jq -e '.structured_output | type == "object"' "$raw" >/dev/null 2>&1; then
    jq '.structured_output' "$raw" > "$out"
  elif jq -e '.result | type == "object"' "$raw" >/dev/null 2>&1; then
    jq '.result' "$raw" > "$out"
  elif jq -e '.result | type == "string"' "$raw" >/dev/null 2>&1; then
    jq -r '.result' "$raw" | jq '.' > "$out" 2>/dev/null
  else
    return 1
  fi
}

validate_verdict_shape() {
  jq -e '
    type == "object"
    and (.Decision == "proceed" or .Decision == "revise" or .Decision == "escalate")
    and (."Artifact-hash" | type == "string" and test("^[a-f0-9]{64}$"))
    and (.Uncertainties | type == "string" and length > 0)
    and (.Rationale | type == "string" and length > 0)
    and (."Required-changes" | type == "string" and length > 0)
    and (.Escalation | type == "string" and length > 0)
    and (.Ledger | type == "string" and length > 0)
  ' "$1" >/dev/null 2>&1
}

if [ "$RUNTIME" = "claude" ]; then
  CLAUDE_BIN="${CLAUDE_BIN:-claude}"
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || fail "Claude CLI not found: $CLAUDE_BIN"
  TASK_PROMPT="$(build_task_prompt "$CTX" "$ARTIFACT_BASE")"
  audit_task_prompt "$RUNTIME" "$TASK_PROMPT"
  RAW_CLAUDE="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-claude-raw.json"
  SYSTEM_PROMPT="You are The Delegate cold reviewer. Do not load CLAUDE.md. Do not act as the Conductor."
  BUDGET="${DELEGATE_MAX_USD:-5.00}"

  (
    cd "$CTX" &&
    "$CLAUDE_BIN" -p \
      --system-prompt "$SYSTEM_PROMPT" \
      --model "$MODEL" \
      --output-format json \
      --json-schema "$(cat "$SCHEMA")" \
      --tools "Read" \
      --add-dir "$CTX" \
      --setting-sources "" \
      --no-session-persistence \
      --max-budget-usd "$BUDGET" \
      "$TASK_PROMPT" < /dev/null
  ) > "$RAW_CLAUDE" 2> "$STDERR_PATH"
  cli_rc=$?
  if [ "$cli_rc" -ne 0 ]; then
    fail "Claude reviewer exited $cli_rc (see $STDERR_PATH)"
  fi
  cp "$RAW_CLAUDE" "$ENVELOPE_PATH" || fail "cannot save Claude envelope"
  : > "$EVENTS_PATH"
  extract_claude_verdict "$RAW_CLAUDE" "$VERDICT_PATH" \
    || fail "Claude reviewer returned no structured verdict"
else
  CODEX_BIN="${CODEX_BIN:-codex}"
  command -v "$CODEX_BIN" >/dev/null 2>&1 || fail "Codex CLI not found: $CODEX_BIN"

  SNAP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bureau-cold-review.XXXXXX")" \
    || fail "cannot create isolated Codex snapshot"
  cleanup_snapshot() {
    rm -rf "$SNAP_ROOT"
  }
  trap cleanup_snapshot EXIT
  SNAP_CTX="$SNAP_ROOT/staged"
  mkdir -p "$SNAP_CTX" || fail "cannot create isolated Codex context"
  cp -R "$CTX/." "$SNAP_CTX/" || fail "cannot copy staged context into isolated Codex snapshot"
  SNAP_CTX="$(cd "$SNAP_CTX" && pwd -P)" || fail "cannot resolve isolated Codex context"

  # Permission Profiles are most-specific-path wins. The temporary workspace is
  # read-only; the live run, target repo, framework, and conversation/config
  # stores are explicitly denied. Network tools are disabled. The model receives
  # snapshot paths only.
  fs_rules='":minimal"="read",":workspace_roots"={"."="read"}'
  append_deny() {
    deny_path="$1"
    [ -n "$deny_path" ] || return 0
    quoted="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$deny_path")"
    case ",$fs_rules," in
      *,"$quoted"'="deny"',*) return 0 ;;
    esac
    fs_rules="${fs_rules},${quoted}=\"deny\""
  }

  append_deny "$RUN_DIR"
  append_deny "$CTX"
  append_deny "$ROOT"
  append_deny "${HOME:-}"
  append_deny "${CODEX_HOME:-${HOME:-}/.codex}"
  append_deny "${HOME:-}/.claude"
  append_deny "${HOME:-}/.novadiem"
  TARGET_REPO="$(jq -r '.target_repo // empty' "$RUN_DIR/state.json" 2>/dev/null)"
  case "$TARGET_REPO" in
    /*) append_deny "$TARGET_REPO" ;;
  esac

  PERMISSIONS="{bureau-review={filesystem={${fs_rules}},network={enabled=false}}}"
  TASK_PROMPT="$(build_task_prompt "$SNAP_CTX" "$ARTIFACT_BASE")"
  audit_task_prompt "$RUNTIME" "$TASK_PROMPT"
  LAST_MESSAGE="$SNAP_ROOT/last-message.json"

  "$CODEX_BIN" --ask-for-approval never exec \
    --ephemeral \
    --ignore-user-config \
    --ignore-rules \
    --skip-git-repo-check \
    --color never \
    -C "$SNAP_CTX" \
    -m "$MODEL" \
    -c "model_reasoning_effort=\"$REASONING_EFFORT\"" \
    -c 'default_permissions="bureau-review"' \
    -c "permissions=$PERMISSIONS" \
    --output-schema "$CODEX_SCHEMA" \
    -o "$LAST_MESSAGE" \
    --json \
    "$TASK_PROMPT" \
    > "$EVENTS_PATH" \
    2> "$STDERR_PATH"
  cli_rc=$?
  if [ "$cli_rc" -ne 0 ]; then
    fail "Codex reviewer exited $cli_rc (see $STDERR_PATH)"
  fi
  [ -s "$LAST_MESSAGE" ] || fail "Codex reviewer returned no final message"
  jq '.' "$LAST_MESSAGE" > "$VERDICT_PATH" 2>/dev/null \
    || fail "Codex reviewer final message was not JSON"

  jq -s --slurpfile verdict "$VERDICT_PATH" '
    [.[] | select(.type == "turn.completed")] as $turns
    | ($turns[-1].usage // {}) as $u
    | (($u.input_tokens // 0) | if type == "number" then . else 0 end) as $all_input
    | (($u.cached_input_tokens // 0) | if type == "number" then . else 0 end) as $cached
    | (($u.cache_write_input_tokens // 0) | if type == "number" then . else 0 end) as $cache_write
    | (($u.output_tokens // 0) | if type == "number" then . else 0 end) as $output
    | {
        type: "bureau-cold-review-result",
        runtime: "openai",
        result: $verdict[0],
        num_turns: ($turns | length),
        usage: {
          input_tokens: ([$all_input - $cached, 0] | max),
          cache_creation_input_tokens: $cache_write,
          cache_read_input_tokens: $cached,
          output_tokens: $output
        }
      }
      + (if ($turns | length) == 0
         then {_note: "Codex JSONL contained no turn.completed usage event"}
         else {} end)
  ' "$EVENTS_PATH" > "$ENVELOPE_PATH" 2>/dev/null \
    || fail "cannot normalize Codex reviewer usage envelope"
fi

validate_verdict_shape "$VERDICT_PATH" \
  || fail "reviewer verdict does not satisfy the required common shape"

jq -cn \
  --arg runtime "$RUNTIME" \
  --arg model "$MODEL" \
  --arg reasoning_effort "$REASONING_EFFORT" \
  --arg verdict_path "$VERDICT_PATH" \
  --arg envelope_path "$ENVELOPE_PATH" \
  --arg events_path "$EVENTS_PATH" \
  --arg stderr_path "$STDERR_PATH" \
  '{
    runtime: $runtime,
    model: $model,
    reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
    verdict_path: $verdict_path,
    envelope_path: $envelope_path,
    events_path: $events_path,
    stderr_path: $stderr_path
  }'
