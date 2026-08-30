#!/usr/bin/env bash
# run-codex-spark-specialist.sh — one-shot Spark transport for a qualified Mage prompt.
#
# Usage:
#   run-codex-spark-specialist.sh <RUN_DIR> <WORKTREE> <PROMPT_FILE> <ATTEMPT_ID>
#
# This is deliberately not a general Codex subagent launcher. The native Codex
# collaboration transport currently rejects Spark as a child-agent model, while
# `codex exec` can launch it. This helper admits exactly one execution profile:
# a first-pass, vetted `execute-plan` prompt tagged `granular-ui-fast`, owned by
# The Mage, and run in a clean worktree. Sol remains the role default and the
# only fallback.

set -u
umask 077

if [ "$#" -ne 4 ]; then
  echo "run-codex-spark-specialist: usage: <RUN_DIR> <WORKTREE> <PROMPT_FILE> <ATTEMPT_ID>" >&2
  exit 2
fi

RUN_DIR="$1"
WORKTREE="$2"
PROMPT_FILE="$3"
ATTEMPT_ID="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING="$RUN_DIR/model-routing.json"
STATE="$RUN_DIR/state.json"
PROFILE_ID="granular-ui-fast"

fail() {
  echo "run-codex-spark-specialist: $*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

if [[ ! "$ATTEMPT_ID" =~ ^mage-[1-9][0-9]*$ ]]; then
  fail "attempt id must be mage-<positive integer>: $ATTEMPT_ID"
fi

[ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
[ -d "$WORKTREE" ] || fail "WORKTREE is not a directory: $WORKTREE"
[ -f "$PROMPT_FILE" ] || fail "prompt file does not exist: $PROMPT_FILE"
[ ! -L "$PROMPT_FILE" ] || fail "prompt file must not be a symlink"
[ -s "$ROUTING" ] || fail "model-routing.json is absent or empty"
[ -s "$STATE" ] || fail "state.json is absent or empty"

RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || fail "cannot resolve RUN_DIR"
WORKTREE="$(cd "$WORKTREE" && pwd -P)" || fail "cannot resolve WORKTREE"
PROMPT_DIR="$(cd "$(dirname "$PROMPT_FILE")" && pwd -P)" || fail "cannot resolve prompt directory"
PROMPT_FILE="$PROMPT_DIR/$(basename "$PROMPT_FILE")"
ROUTING="$RUN_DIR/model-routing.json"
STATE="$RUN_DIR/state.json"

[ "$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)" = "openai" ] \
  || fail "Spark exec profile requires runtime=openai"
[ "$(jq -r '.workflow // empty' "$STATE" 2>/dev/null)" = "execute-plan" ] \
  || fail "Spark exec profile is restricted to execute-plan"

RECORDED_WORKTREE="$(jq -r '.git.worktree_path // empty' "$STATE" 2>/dev/null)"
[ -n "$RECORDED_WORKTREE" ] || fail "state.json has no git.worktree_path"
RECORDED_WORKTREE="$(cd "$RECORDED_WORKTREE" 2>/dev/null && pwd -P)" \
  || fail "recorded worktree is unavailable: $RECORDED_WORKTREE"
[ "$RECORDED_WORKTREE" = "$WORKTREE" ] \
  || fail "WORKTREE does not match state.json#git.worktree_path"

PROFILE_QUERY='.roles.mage.executionProfiles["granular-ui-fast"]'
MODEL="$(jq -r "$PROFILE_QUERY.model // empty" "$ROUTING" 2>/dev/null)"
EFFORT="$(jq -r "$PROFILE_QUERY.reasoningEffort // empty" "$ROUTING" 2>/dev/null)"
TRANSPORT="$(jq -r "$PROFILE_QUERY.transport // empty" "$ROUTING" 2>/dev/null)"
HELPER="$(jq -r "$PROFILE_QUERY.helper // empty" "$ROUTING" 2>/dev/null)"

[ "$MODEL" = "gpt-5.3-codex-spark" ] || fail "resolved profile model is not Spark"
[ "$EFFORT" = "high" ] || fail "resolved Spark effort must be high"
[ "$TRANSPORT" = "codex-exec-one-shot" ] || fail "resolved profile transport is unsupported: $TRANSPORT"
[ "$HELPER" = "scripts/run-codex-spark-specialist.sh" ] || fail "resolved profile helper does not name this script"

CODER_DECLARATIONS="$(grep -Ec '^Coder:' "$PROMPT_FILE" || true)"
CODER_COUNT="$(grep -Ec '^Coder:[[:space:]]*The Mage[[:space:]]*$' "$PROMPT_FILE" || true)"
PROFILE_DECLARATIONS="$(grep -Ec '^Execution-profile:' "$PROMPT_FILE" || true)"
PROFILE_COUNT="$(grep -Ec '^Execution-profile:[[:space:]]*granular-ui-fast[[:space:]]*$' "$PROMPT_FILE" || true)"
[ "$CODER_DECLARATIONS" -eq 1 ] && [ "$CODER_COUNT" -eq 1 ] \
  || fail "prompt must contain exactly one coder declaration naming The Mage"
[ "$PROFILE_DECLARATIONS" -eq 1 ] && [ "$PROFILE_COUNT" -eq 1 ] \
  || fail "prompt must contain exactly one execution-profile declaration naming granular-ui-fast"
if grep -Eqi '^Release-step:[[:space:]]*yes[[:space:]]*$' "$PROMPT_FILE"; then
  fail "release steps may not use the Spark execution profile"
fi

PROMPT_STEP="$(basename "$PROMPT_FILE" | sed -n 's/^\([0-9][0-9]*\)-.*\.md$/\1/p')"
[ -n "$PROMPT_STEP" ] || fail "prompt filename must be NN-<slug>.md"

GATE_OUTPUT="$(bash "$SCRIPT_DIR/spawn-gate.sh" "$RUN_DIR" 2>&1)"
GATE_RC=$?
[ "$GATE_RC" -eq 0 ] || fail "spawn gate failed: $GATE_OUTPUT"

command -v git >/dev/null 2>&1 || fail "git is required"
git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "WORKTREE is not a git worktree"
PRE_STATUS="$(git -C "$WORKTREE" status --porcelain --untracked-files=all --ignore-submodules=none)"
[ -z "$PRE_STATUS" ] || fail "Spark requires a clean worktree before dispatch"
BASE_HEAD="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)" || fail "cannot read worktree HEAD"

if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  POINTER_FILE="$BUREAU_POINTER_FILE"
else
  POINTER_DIR="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  POINTER_KEY="$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')"
  POINTER_FILE="$POINTER_DIR/$POINTER_KEY"
fi
[ -f "$POINTER_FILE" ] || fail "run-scope file is absent: $POINTER_FILE"
POINTER_RUN="$(jq -r '.run_dir // empty' "$POINTER_FILE" 2>/dev/null)"
RUN_NONCE="$(jq -r '.nonce // empty' "$POINTER_FILE" 2>/dev/null)"
[ "$POINTER_RUN" = "$RUN_DIR" ] || fail "run-scope file belongs to another run"
[ -n "$RUN_NONCE" ] || fail "run-scope file has no nonce"

CODEX_BIN="${CODEX_BIN:-codex}"
command -v "$CODEX_BIN" >/dev/null 2>&1 || fail "Codex CLI not found: $CODEX_BIN"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bureau-spark.XXXXXX")" \
  || fail "cannot create private temporary directory"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

LAUNCH_PROMPT="$TMP_ROOT/prompt.md"
RAW_EVENTS="$TMP_ROOT/events.jsonl"
RAW_STDERR="$TMP_ROOT/stderr.log"
RAW_LAST="$TMP_ROOT/last-message.md"
NONCE_PATTERN="$TMP_ROOT/nonce-pattern"

printf '%s' "$RUN_NONCE" > "$NONCE_PATTERN" || fail "cannot stage private nonce check"

{
  printf '%s\n' "You are running as The Mage (the frontend coder) in The Bureau, launched with a fresh one-shot Codex context."
  printf '\nBUREAU_ROLE: mage\n'
  printf 'RUN_DIR: %s\n' "$RUN_DIR"
  printf 'WORKTREE: %s\n' "$WORKTREE"
  printf 'Workflow: execute-plan\n'
  printf 'Role mode: execute-plan\n'
  printf 'Attempt ID: %s\n' "$ATTEMPT_ID"
  printf 'Run nonce: %s\n' "$RUN_NONCE"
  printf 'Execution profile: %s\n\n' "$PROFILE_ID"
  printf '1. Read in full and adopt your role: %s/agents/frontend.md\n' "$ROOT"
  printf '2. Read and execute exactly this one vetted prompt: %s\n' "$PROMPT_FILE"
  printf '%s\n' '3. This fast profile is valid only for a bounded, text-only change to one existing frontend surface. If the work needs new state, API/navigation/contract changes, a dependency, generated files, another coder, image judgment, auth/data/value handling, an external action, or broader design/architecture, make no edits and end with: SPARK PROFILE INELIGIBLE — <reason>.'
  printf '%s\n' '4. Work only in WORKTREE, run the prompt checkpoint, commit the finished change, and end with the exact Mage handoff block. Do not spawn subagents.'
  printf '%s\n' '5. Never repeat or write the run nonce into a file, command, handoff, log, or final response.'
} > "$LAUNCH_PROMPT" || fail "cannot build private launch prompt"

OUT_PARENT="$RUN_DIR/codex-specialists"
[ ! -L "$OUT_PARENT" ] || fail "specialist output parent must not be a symlink"
mkdir -p "$OUT_PARENT" || fail "cannot create specialist output parent"
OUT_DIR="$OUT_PARENT/$ATTEMPT_ID"
[ ! -e "$OUT_DIR" ] || fail "attempt output already exists: $OUT_DIR"
mkdir "$OUT_DIR" || fail "cannot create attempt output directory"

ENVELOPE_PATH="$OUT_DIR/envelope.json"
HANDOFF_PATH="$OUT_DIR/handoff.md"
STDERR_PATH="$OUT_DIR/stderr.log"

"$CODEX_BIN" --ask-for-approval never exec \
  --strict-config \
  --ephemeral \
  --ignore-user-config \
  --color never \
  --sandbox workspace-write \
  -C "$WORKTREE" \
  -m "$MODEL" \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  -o "$RAW_LAST" \
  --json \
  - \
  < "$LAUNCH_PROMPT" \
  > "$RAW_EVENTS" \
  2> "$RAW_STDERR"
CODEX_RC=$?

# Persist diagnostics only after removing any line that contains the run nonce.
grep -Fv -- "$RUN_NONCE" "$RAW_STDERR" > "$STDERR_PATH" 2>/dev/null || : > "$STDERR_PATH"

jq -s --arg model "$MODEL" --arg effort "$EFFORT" '
  [.[] | select(.type == "turn.completed")] as $turns
  | ($turns[-1].usage // {}) as $u
  | (($u.input_tokens // 0) | if type == "number" then . else 0 end) as $allInput
  | (($u.cached_input_tokens // 0) | if type == "number" then . else 0 end) as $cached
  | (($u.cache_write_input_tokens // 0) | if type == "number" then . else 0 end) as $cacheWrite
  | (($u.output_tokens // 0) | if type == "number" then . else 0 end) as $output
  | {
      type: "bureau-codex-specialist-result",
      runtime: "openai",
      transport: "codex-exec-one-shot",
      requested_model: $model,
      reasoning_effort: $effort,
      num_turns: ($turns | length),
      usage: {
        input_tokens: ([$allInput - $cached, 0] | max),
        cache_creation_input_tokens: $cacheWrite,
        cache_read_input_tokens: $cached,
        output_tokens: $output
      }
    }
    + (if ($turns | length) == 0
       then {_note: "Codex JSONL contained no turn.completed usage event"}
       else {} end)
' "$RAW_EVENTS" > "$ENVELOPE_PATH" 2>/dev/null \
  || printf '%s\n' '{"type":"bureau-codex-specialist-result","runtime":"openai","transport":"codex-exec-one-shot","num_turns":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"_note":"Codex JSONL could not be normalized"}' > "$ENVELOPE_PATH"

TURN_COUNT="$(jq -r 'if (.num_turns | type) == "number" then .num_turns else 0 end' "$ENVELOPE_PATH" 2>/dev/null || printf '0')"
case "$TURN_COUNT" in
  ''|*[!0-9]*) TURN_COUNT=0 ;;
esac

POST_STATUS="$(git -C "$WORKTREE" status --porcelain --untracked-files=all --ignore-submodules=none)"
POST_HEAD="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || printf '')"
FALLBACK_SAFE=false
if [ "$POST_HEAD" = "$BASE_HEAD" ] && [ -z "$POST_STATUS" ]; then
  FALLBACK_SAFE=true
fi

STATUS="failed"
REASON="codex-exit-$CODEX_RC"
EXIT_CODE=76

valid_mage_handoff() {
  _handoff="$1"
  _expected_step="$2"

  [ "$(grep -Ec "^THE MAGE — BUILT ${_expected_step}[[:space:]]*$" "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Consumed:[[:space:]]*[^[:space:]]' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Produced:[[:space:]]*[^[:space:]]' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Passing forward:[[:space:]]*$' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Prompt:[[:space:]]*[^[:space:]]' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Checkpoint:[[:space:]]*green([[:space:]]|$)' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Review size:.*matches prompt Reviewability yes([[:space:]]|$)' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^New packages installed:[[:space:]]*none[[:space:]]*$' "$_handoff" || true)" -eq 1 ] \
    && [ "$(grep -Ec '^Out-of-scope issues noticed \(did NOT touch\):[[:space:]]*[^[:space:]]' "$_handoff" || true)" -eq 1 ] \
    || return 1

  _marker_line="$(grep -n "^THE MAGE — BUILT ${_expected_step}[[:space:]]*$" "$_handoff" | cut -d: -f1)"
  _consumed_line="$(grep -n '^Consumed:' "$_handoff" | cut -d: -f1)"
  _produced_line="$(grep -n '^Produced:' "$_handoff" | cut -d: -f1)"
  _passing_line="$(grep -n '^Passing forward:[[:space:]]*$' "$_handoff" | cut -d: -f1)"
  _prompt_line="$(grep -n '^Prompt:' "$_handoff" | cut -d: -f1)"
  _checkpoint_line="$(grep -n '^Checkpoint:' "$_handoff" | cut -d: -f1)"
  _review_line="$(grep -n '^Review size:' "$_handoff" | cut -d: -f1)"
  _packages_line="$(grep -n '^New packages installed:' "$_handoff" | cut -d: -f1)"
  _scope_line="$(grep -n '^Out-of-scope issues noticed (did NOT touch):' "$_handoff" | cut -d: -f1)"
  _last_nonempty="$(awk 'NF { line = $0 } END { print line }' "$_handoff")"

  [ "$_marker_line" -lt "$_consumed_line" ] \
    && [ "$_consumed_line" -lt "$_produced_line" ] \
    && [ "$_produced_line" -lt "$_passing_line" ] \
    && [ "$_passing_line" -lt "$_prompt_line" ] \
    && [ "$_prompt_line" -lt "$_checkpoint_line" ] \
    && [ "$_checkpoint_line" -lt "$_review_line" ] \
    && [ "$_review_line" -lt "$_packages_line" ] \
    && [ "$_packages_line" -lt "$_scope_line" ] \
    && awk -v start="$_passing_line" -v stop="$_prompt_line" \
         'NR > start && NR < stop && /^- / { found = 1 } END { exit(found ? 0 : 1) }' "$_handoff" \
    && [[ "$_last_nonempty" == 'Out-of-scope issues noticed (did NOT touch):'* ]]
}

if [ "$CODEX_RC" -eq 0 ]; then
  if grep -Eqi 'model["./_ -]*(re)?rout|fallback["./_ -]*model' "$RAW_EVENTS" "$RAW_STDERR"; then
    REASON="model-reroute-detected"
  elif [ "$TURN_COUNT" -lt 1 ]; then
    REASON="missing-turn-completed"
  elif [ ! -s "$RAW_LAST" ]; then
    REASON="missing-final-message"
  elif grep -Fq -- "$RUN_NONCE" "$RAW_LAST"; then
    REASON="nonce-leaked-in-handoff"
  elif grep -Eq '^SPARK PROFILE INELIGIBLE — .+' "$RAW_LAST"; then
    REASON="profile-ineligible"
  elif ! valid_mage_handoff "$RAW_LAST" "$PROMPT_STEP"; then
    REASON="invalid-mage-handoff"
  elif [ -n "$POST_STATUS" ]; then
    REASON="worktree-dirty-after-spark"
  elif [ -z "$POST_HEAD" ] || [ "$POST_HEAD" = "$BASE_HEAD" ]; then
    REASON="spark-made-no-commit"
  elif ! git -C "$WORKTREE" merge-base --is-ancestor "$BASE_HEAD" "$POST_HEAD" >/dev/null 2>&1; then
    REASON="spark-rewrote-base-head"
  elif git -C "$WORKTREE" diff --quiet "$BASE_HEAD" "$POST_HEAD" --; then
    REASON="spark-commit-has-no-tree-change"
  elif git -C "$WORKTREE" grep -Fq -f "$NONCE_PATTERN" "$POST_HEAD" --; then
    REASON="nonce-leaked-in-commit"
  else
    cp "$RAW_LAST" "$HANDOFF_PATH" || fail "cannot persist validated Mage handoff"
    STATUS="complete"
    REASON="complete"
    FALLBACK_SAFE=false
    EXIT_CODE=0
  fi
fi

# Exit 75 is reserved for a failed Spark attempt whose observable git state is
# unchanged. That includes a clean profile self-decline with a zero Codex exit.
if [ "$STATUS" = "failed" ] && [ "$FALLBACK_SAFE" = true ]; then
  EXIT_CODE=75
fi

jq -cn \
  --arg status "$STATUS" \
  --arg reason "$REASON" \
  --arg profile "$PROFILE_ID" \
  --arg model "$MODEL" \
  --arg effort "$EFFORT" \
  --arg handoff "$HANDOFF_PATH" \
  --arg envelope "$ENVELOPE_PATH" \
  --arg stderr "$STDERR_PATH" \
  --argjson fallback_safe "$FALLBACK_SAFE" \
  '{
    status: $status,
    reason: $reason,
    profile: $profile,
    transport: "codex-exec-one-shot",
    actual_model: $model,
    reasoning_effort: $effort,
    fallback_safe: $fallback_safe,
    handoff_path: (if $status == "complete" then $handoff else null end),
    envelope_path: $envelope,
    stderr_path: $stderr
  }'

exit "$EXIT_CODE"
