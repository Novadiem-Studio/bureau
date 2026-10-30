#!/usr/bin/env bash
# One deterministic cross-model pass for the write-article family of workflows, in one of two
# modes:
#   improve (default) — "improve this draft": the model returns a full revised candidate that
#                       the Scribe reconciles into the next version.
#   memo              — "read this and write a memo": the model returns ideas / objections as a
#                       memo the Scribe WEIGHS, never merges. Used by the ideas pass (after the
#                       outline) and the skeptic pass (after the revise step).
#
# Makes no routing decisions and promotes nothing: the caller supplies model, draft,
# instruction, and out-file. The script makes ONE model call (an OpenRouter chat-completions
# POST, or one local `codex exec` one-shot for a codex: model) and writes the
# candidate to <out-file> ONLY when every integrity check passes — otherwise it writes
# nothing, errors to stderr, and exits non-zero, so "out-file exists" reliably means
# "this candidate cleared all checks". The prior draft is never touched on failure.
#
# Usage:
#   model-pass.sh <model-spec> <draft-file> <instruction-file> <out-file> [--run-dir RUN_DIR] [--mode improve|memo]
#
# Arguments:
#   <model-spec>        provider-prefixed model id, e.g. openrouter:x-ai/grok-4.3 or
#                       codex:gpt-6.1-sol (the local Codex CLI, on Robin's subscription)
#   <draft-file>        absolute path to the draft to improve (must exist, non-empty)
#   <instruction-file>  absolute path to the instruction file (must exist, non-empty)
#   <out-file>          absolute path to write the candidate (written only on full success;
#                       its parent directory must already exist)
#   --run-dir RUN_DIR   optional; when given, append one external-action log line to
#                       RUN_DIR/log.md (model, mode, bytes in/out, finish_reason, status, exit)
#   --mode MODE         optional; `improve` (default) or `memo`. Selects the user-message frame
#                       and the length integrity check: improve requires 50%-300% of the input
#                       bytes (a rewrite of the same piece); memo requires 300B-40000B absolute
#                       (a memo about a short outline is legitimately longer than its input).
#
# Exit codes:
#   0   candidate written to <out-file>
#   1   bad arguments or missing input files (before any network call)
#   2   provider error (non-2xx HTTP, curl failure, or .error in the response body; for
#       codex:, a non-zero `codex exec` exit or the MODEL_PASS_CODEX_TIMEOUT timeout)
#   3   integrity check failed (finish_reason != "stop", empty/whitespace content,
#       output bytes outside the mode's bound: 50%-300% of input for improve,
#       300B-40000B absolute for memo; or, in improve mode, a markdown link target
#       present in the draft is missing from the candidate — scripts/link-set-check.sh.
#       Set MODEL_PASS_ALLOW_LINK_DROP=1 to waive the link check for a pass whose
#       instruction deliberately permits removing links)
#   4   OpenRouter key missing (OPENROUTER_API_KEY absent and no configured keystore), or
#       for codex:, the Codex CLI is not on PATH (override with CODEX_BIN)
#
# Two provider prefixes are routed. openrouter: makes the chat-completions POST; the body is
# built with `jq -n` (the draft is arbitrary markdown — never string-interpolated). codex: runs
# the local Codex CLI once (Robin, 2026-10-12, issue #107): `codex exec`, ephemeral, user config
# ignored, read-only sandbox, launched from an empty temp dir so it cannot read any repo, no
# approvals. The prompt is the instruction file, then the mode frame, then the draft, on stdin.
# Codex reports no finish_reason, so the log records `codex-exit-0` in its place; every
# content check below (non-empty, length bounds, link set) applies to both arms.
# Codex knobs: MODEL_PASS_CODEX_EFFORT (default medium), MODEL_PASS_CODEX_TIMEOUT seconds
# (default 900). Bash 3.2 / macOS portable.
#
# Spec refs: plan-write-article-workflow.md §1; plan.md chunk 1.

set -euo pipefail

readonly KEYSTORE="${OPENROUTER_KEYSTORE:-}"
readonly OPENROUTER_URL="https://openrouter.ai/api/v1/chat/completions"
readonly MAX_TIME=120
readonly MAX_TOKENS=8192
readonly TEMPERATURE=0.3
readonly MEMO_MIN_BYTES=300
readonly MEMO_MAX_BYTES=40000
readonly CODEX_EFFORT="${MODEL_PASS_CODEX_EFFORT:-medium}"
readonly CODEX_TIMEOUT="${MODEL_PASS_CODEX_TIMEOUT:-900}"
CODEX_BIN="${CODEX_BIN:-codex}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
readonly SCRIPT_DIR

usage() {
  echo "Usage: model-pass.sh <model-spec> <draft-file> <instruction-file> <out-file> [--run-dir RUN_DIR] [--mode improve|memo]" >&2
  exit 1
}

# die <exit-code> <message...> — emit to stderr and exit with the given code.
die() {
  local code="$1"; shift
  echo "model-pass: $*" >&2
  exit "$code"
}

# ── argument handling ─────────────────────────────────────────────────────────
# Exactly 4 positional args, plus an optional `--run-dir RUN_DIR` pair anywhere
# after them. Parse the optional pair out first, then require 4 positionals.

RUN_DIR=""
MODE="improve"
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      [ "$#" -ge 2 ] || usage
      RUN_DIR="$2"
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || usage
      MODE="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

[ "${#POSITIONAL[@]}" -eq 4 ] || usage
case "$MODE" in
  improve|memo) ;;
  *) die 1 "unknown --mode '$MODE' (expected improve or memo)" ;;
esac

MODEL_SPEC="${POSITIONAL[0]}"
DRAFT_FILE="${POSITIONAL[1]}"
INSTRUCTION_FILE="${POSITIONAL[2]}"
OUT_FILE="${POSITIONAL[3]}"

command -v jq >/dev/null 2>&1   || die 1 "jq is required but not found on PATH"

# ── input validation (fail fast, name the file, before any network call) ────────

[ -f "$DRAFT_FILE" ]       || die 1 "draft-file does not exist: $DRAFT_FILE"
[ -s "$DRAFT_FILE" ]       || die 1 "draft-file is empty: $DRAFT_FILE"
[ -f "$INSTRUCTION_FILE" ] || die 1 "instruction-file does not exist: $INSTRUCTION_FILE"
[ -s "$INSTRUCTION_FILE" ] || die 1 "instruction-file is empty: $INSTRUCTION_FILE"

OUT_DIR="$(dirname "$OUT_FILE")"
[ -d "$OUT_DIR" ] || die 1 "out-file parent directory does not exist: $OUT_DIR"

# Provider prefix: openrouter: or codex:. Split on the first colon.
case "$MODEL_SPEC" in
  openrouter:?*)
    PROVIDER="openrouter"
    MODEL_ID="${MODEL_SPEC#openrouter:}"
    ;;
  codex:?*)
    PROVIDER="codex"
    MODEL_ID="${MODEL_SPEC#codex:}"
    ;;
  *)
    die 1 "unroutable provider prefix in '$MODEL_SPEC' — expected openrouter: or codex:"
    ;;
esac

if [ "$PROVIDER" = "openrouter" ]; then
  command -v curl >/dev/null 2>&1 || die 1 "curl is required but not found on PATH"

  # ── OpenRouter key (loud-fail if absent; never echo the secret) ───────────────
  if [ -z "${OPENROUTER_API_KEY:-}" ] && [ -n "$KEYSTORE" ]; then
    [ -f "$KEYSTORE" ] || die 4 "keystore not found: $KEYSTORE"
    # shellcheck disable=SC1090
    . "$KEYSTORE"
  fi
  [ -n "${OPENROUTER_API_KEY:-}" ] || die 4 "OPENROUTER_API_KEY empty or unset; export it or set OPENROUTER_KEYSTORE"
else
  command -v "$CODEX_BIN" >/dev/null 2>&1 || die 4 "Codex CLI not found: $CODEX_BIN (install it or set CODEX_BIN)"
  command -v perl >/dev/null 2>&1 || die 1 "perl is required for the codex timeout but not found on PATH"
  case "$CODEX_TIMEOUT" in
    ''|*[!0-9]*) die 1 "MODEL_PASS_CODEX_TIMEOUT must be whole seconds, got '$CODEX_TIMEOUT'" ;;
  esac
fi

# ── input byte count (load-bearing for the length-delta check) ──────────────────
# wc -c counts bytes (not characters), which is what we compare output against.
INPUT_BYTES="$(wc -c < "$DRAFT_FILE" | tr -d '[:space:]')"

# ── log helper (only writes when --run-dir given AND the dir exists) ────────────
# Appends one external-action line per the plan's audit-trail format. Best-effort:
# a logging failure must never mask the real exit code, so guard with `|| true`.
log_action() {
  local status="$1" exit_code="$2" finish="$3" out_bytes="$4"
  [ -n "$RUN_DIR" ] || return 0
  [ -d "$RUN_DIR" ] || return 0
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '[EXTERNAL-ACTION] model-pass: model=%s mode=%s bytes_in=%s bytes_out=%s finish_reason=%s status=%s exit=%s ts=%s\n' \
      "$MODEL_SPEC" "$MODE" "$INPUT_BYTES" "$out_bytes" "$finish" "$status" "$exit_code" "$ts" \
      >> "$RUN_DIR/log.md"
  } || true
}

# die_logged <exit-code> <finish_reason> <out_bytes> <message...> — log a failure
# line then die. Used after the POST so failures land in the audit trail too.
die_logged() {
  local code="$1" finish="$2" out_bytes="$3"; shift 3
  log_action "fail" "$code" "$finish" "$out_bytes"
  die "$code" "$@"
}

# ── build the request body with jq -n (NEVER string-interpolate the draft) ──────
# The user-message frame is the only mode-dependent part of the request: improve asks for a
# revised draft, memo asks for a memo about the material. The instruction file carries the rest.
if [ "$MODE" = "memo" ]; then
  USER_FRAME="Read the following material and write your memo:"
else
  USER_FRAME="Improve the following draft:"
fi

# Temp files for either arm, removed on any exit. OUT_TMP is set before the length check.
CODEX_DIR=""
OUT_TMP=""
cleanup() {
  [ -n "$OUT_TMP" ] && rm -f "$OUT_TMP"
  [ -n "$CODEX_DIR" ] && rm -rf "$CODEX_DIR"
  return 0
}
trap cleanup EXIT

if [ "$PROVIDER" = "codex" ]; then
  # ── the one codex exec ──────────────────────────────────────────────────────────
  # An empty temp dir is the working root, so the agent has no repo to read; read-only
  # sandbox, no approvals, no saved session, user config ignored (auth still comes from
  # CODEX_HOME). perl's alarm bounds the run: SIGALRM ends codex and the arm exits 2.
  CODEX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/model-pass-codex.XXXXXX")"
  {
    printf '%s\n\n' "You are running a single text-editing pass. Do not run commands, read files, or edit files. Reply with only the requested text and nothing else."
    cat "$INSTRUCTION_FILE"
    printf '\n\n%s\n\n' "$USER_FRAME"
    cat "$DRAFT_FILE"
  } > "$CODEX_DIR/prompt.md"

  CODEX_RC=0
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$CODEX_TIMEOUT" \
    "$CODEX_BIN" --ask-for-approval never exec \
      --ephemeral \
      --ignore-user-config \
      --skip-git-repo-check \
      --color never \
      --sandbox read-only \
      -C "$CODEX_DIR" \
      -m "$MODEL_ID" \
      -c "model_reasoning_effort=\"$CODEX_EFFORT\"" \
      -o "$CODEX_DIR/last.md" \
      - \
      < "$CODEX_DIR/prompt.md" \
      > "$CODEX_DIR/events.log" \
      2> "$CODEX_DIR/stderr.log" \
    || CODEX_RC=$?

  if [ "$CODEX_RC" -ne 0 ]; then
    if [ "$CODEX_RC" -eq 142 ]; then
      die_logged 2 "codex-timeout" "0" "codex exec exceeded ${CODEX_TIMEOUT}s (MODEL_PASS_CODEX_TIMEOUT)"
    fi
    die_logged 2 "codex-exit-$CODEX_RC" "0" "codex exec exited $CODEX_RC — stderr: $(tail -n 5 "$CODEX_DIR/stderr.log" 2>/dev/null | tr '\n' ' ')"
  fi
  FINISH_REASON="codex-exit-0"
  CONTENT="$(cat "$CODEX_DIR/last.md" 2>/dev/null || true)"
else  # openrouter arm, left unindented so its history stays readable

BODY="$(jq -n \
  --arg model "$MODEL_ID" \
  --argjson max_tokens "$MAX_TOKENS" \
  --argjson temperature "$TEMPERATURE" \
  --arg frame "$USER_FRAME" \
  --rawfile instruction "$INSTRUCTION_FILE" \
  --rawfile draft "$DRAFT_FILE" \
  '{
    model: $model,
    max_tokens: $max_tokens,
    temperature: $temperature,
    messages: [
      {role: "system", content: $instruction},
      {role: "user",   content: ($frame + "\n\n" + $draft)}
    ]
  }')"

# ── the one POST ────────────────────────────────────────────────────────────────
# Capture the HTTP status by appending it on its own trailing line via -w, then
# split body from status. `--max-time` bounds it; curl's own failure (timeout,
# DNS, connection refused) is exit 2 here, not a thrown set -e abort.
HTTP_STATUS=""
RESPONSE=""
RAW="$(curl -sS --max-time "$MAX_TIME" \
  -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://devweb.org" \
  -H "X-Title: devweb write-article" \
  -w $'\n%{http_code}' \
  -d "$BODY" \
  "$OPENROUTER_URL")" || die_logged 2 "none" "0" "curl failed (timeout/connection/transport) calling $OPENROUTER_URL"

# Last line is the status code; everything before it is the response body.
HTTP_STATUS="${RAW##*$'\n'}"
RESPONSE="${RAW%$'\n'*}"

# ── integrity checks (ALL must pass; any failure → write nothing, exit non-zero) ─

# a. HTTP 2xx
case "$HTTP_STATUS" in
  2[0-9][0-9]) ;;
  *) die_logged 2 "none" "0" "non-2xx HTTP status $HTTP_STATUS from provider — body: $RESPONSE" ;;
esac

# b. no .error field in the response
if printf '%s' "$RESPONSE" | jq -e 'has("error") and (.error != null)' >/dev/null 2>&1; then
  ERR_MSG="$(printf '%s' "$RESPONSE" | jq -r '.error | if type == "object" then (.message // tostring) else tostring end' 2>/dev/null || echo "unparseable error field")"
  die_logged 2 "none" "0" "provider returned an error: $ERR_MSG"
fi

# c. finish_reason must be EXACTLY the string "stop" (null/absent/"length"/anything else → reject)
FINISH_REASON="$(printf '%s' "$RESPONSE" | jq -r '.choices[0].finish_reason // "null"' 2>/dev/null || echo "unparseable")"
if [ "$FINISH_REASON" != "stop" ]; then
  die_logged 3 "$FINISH_REASON" "0" "finish_reason is '$FINISH_REASON', expected exactly 'stop' (truncation/filter/refusal → rejecting candidate)"
fi

CONTENT="$(printf '%s' "$RESPONSE" | jq -r '.choices[0].message.content // ""' 2>/dev/null || echo "")"
fi  # end openrouter arm

# d. non-empty / non-whitespace content (both arms)

if [ -z "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ]; then
  die_logged 3 "$FINISH_REASON" "0" "model returned empty or whitespace-only content"
fi

# e. length sanity — bytes, integer arithmetic. improve: reject < 50% or > 300% of input;
#    memo: reject < MEMO_MIN_BYTES or > MEMO_MAX_BYTES.
#    Write the candidate to a temp file FIRST (this is also the atomic-write staging),
#    measure its byte count, and only mv into place after this final check passes.
OUT_TMP="${OUT_FILE}.tmp.$$"
printf '%s' "$CONTENT" > "$OUT_TMP"
OUTPUT_BYTES="$(wc -c < "$OUT_TMP" | tr -d '[:space:]')"

if [ "$MODE" = "memo" ]; then
  # A memo is not a rewrite: its length is unrelated to the input's. Absolute bounds catch a
  # refusal / one-liner (too short) or a runaway (too long).
  LOWER="$MEMO_MIN_BYTES"
  UPPER="$MEMO_MAX_BYTES"
else
  LOWER=$(( INPUT_BYTES * 50 / 100 ))
  UPPER=$(( INPUT_BYTES * 300 / 100 ))
fi
if [ "$OUTPUT_BYTES" -lt "$LOWER" ] || [ "$OUTPUT_BYTES" -gt "$UPPER" ]; then
  rm -f "$OUT_TMP"
  die_logged 3 "$FINISH_REASON" "$OUTPUT_BYTES" \
    "length out of range for mode=${MODE}: output ${OUTPUT_BYTES}B vs input ${INPUT_BYTES}B (allowed ${LOWER}B-${UPPER}B); likely a refusal, summary, or runaway"
fi

# f. link-set invariant (improve mode only). Every improve instruction forbids removing links,
#    but a model can turn them into plain text while staying inside the byte-ratio bound, and
#    the loss then surfaces only as a target build failing a link floor (2026-09-06). Compare
#    link TARGETS as a set; text and order may change. MODEL_PASS_ALLOW_LINK_DROP=1 waives it.
if [ "$MODE" = "improve" ] && [ -z "${MODEL_PASS_ALLOW_LINK_DROP:-}" ]; then
  if ! LINK_ERR="$("$SCRIPT_DIR/link-set-check.sh" "$DRAFT_FILE" "$OUT_TMP" 2>&1)"; then
    rm -f "$OUT_TMP"
    die_logged 3 "$FINISH_REASON" "$OUTPUT_BYTES" \
      "candidate dropped link target(s) the draft carried — rejecting (set MODEL_PASS_ALLOW_LINK_DROP=1 to waive): ${LINK_ERR}"
  fi
fi

# ── atomic write — all checks passed; promote the temp file into place ──────────
mv "$OUT_TMP" "$OUT_FILE"
OUT_TMP=""

log_action "ok" "0" "$FINISH_REASON" "$OUTPUT_BYTES"
exit 0
