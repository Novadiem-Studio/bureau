#!/usr/bin/env bash
# One deterministic "improve this draft" cross-model pass for the write-article workflow.
#
# Makes no routing decisions and promotes nothing: the caller supplies model, draft,
# instruction, and out-file. The script does ONE chat-completions POST and writes the
# candidate to <out-file> ONLY when every integrity check passes — otherwise it writes
# nothing, errors to stderr, and exits non-zero, so "out-file exists" reliably means
# "this candidate cleared all checks". The prior draft is never touched on failure.
#
# Usage:
#   model-pass.sh <model-spec> <draft-file> <instruction-file> <out-file> [--run-dir RUN_DIR]
#
# Arguments:
#   <model-spec>        provider-prefixed model id, e.g. openrouter:x-ai/grok-4.3
#   <draft-file>        absolute path to the draft to improve (must exist, non-empty)
#   <instruction-file>  absolute path to the instruction file (must exist, non-empty)
#   <out-file>          absolute path to write the candidate (written only on full success;
#                       its parent directory must already exist)
#   --run-dir RUN_DIR   optional; when given, append one external-action log line to
#                       RUN_DIR/log.md (model, bytes in/out, finish_reason, status, exit)
#
# Exit codes:
#   0   candidate written to <out-file>
#   1   bad arguments or missing input files (before any network call)
#   2   provider error (non-2xx HTTP, curl failure, or .error in the response body)
#   3   integrity check failed (finish_reason != "stop", empty/whitespace content,
#       or output byte count outside 50%-300% of input)
#   4   OpenRouter key missing (OPENROUTER_API_KEY absent and no configured keystore)
#
# v1 routes the openrouter: provider prefix ONLY. The prefix is the extension seam:
# an openai:/anthropic: direct arm is added only when a model OpenRouter cannot proxy
# forces it. Body is built with `jq -n` (the draft is arbitrary markdown — never
# string-interpolated). Bash 3.2 / macOS portable.
#
# Spec refs: plan-write-article-workflow.md §1; plan.md chunk 1.

set -euo pipefail

readonly KEYSTORE="${OPENROUTER_KEYSTORE:-}"
readonly OPENROUTER_URL="https://openrouter.ai/api/v1/chat/completions"
readonly MAX_TIME=120
readonly MAX_TOKENS=8192
readonly TEMPERATURE=0.3

usage() {
  echo "Usage: model-pass.sh <model-spec> <draft-file> <instruction-file> <out-file> [--run-dir RUN_DIR]" >&2
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
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      [ "$#" -ge 2 ] || usage
      RUN_DIR="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

[ "${#POSITIONAL[@]}" -eq 4 ] || usage

MODEL_SPEC="${POSITIONAL[0]}"
DRAFT_FILE="${POSITIONAL[1]}"
INSTRUCTION_FILE="${POSITIONAL[2]}"
OUT_FILE="${POSITIONAL[3]}"

command -v jq >/dev/null 2>&1   || die 1 "jq is required but not found on PATH"
command -v curl >/dev/null 2>&1 || die 1 "curl is required but not found on PATH"

# ── input validation (fail fast, name the file, before any network call) ────────

[ -f "$DRAFT_FILE" ]       || die 1 "draft-file does not exist: $DRAFT_FILE"
[ -s "$DRAFT_FILE" ]       || die 1 "draft-file is empty: $DRAFT_FILE"
[ -f "$INSTRUCTION_FILE" ] || die 1 "instruction-file does not exist: $INSTRUCTION_FILE"
[ -s "$INSTRUCTION_FILE" ] || die 1 "instruction-file is empty: $INSTRUCTION_FILE"

OUT_DIR="$(dirname "$OUT_FILE")"
[ -d "$OUT_DIR" ] || die 1 "out-file parent directory does not exist: $OUT_DIR"

# Provider prefix: v1 routes openrouter: ONLY. Split on the first colon.
case "$MODEL_SPEC" in
  openrouter:?*)
    MODEL_ID="${MODEL_SPEC#openrouter:}"
    ;;
  *)
    die 1 "unroutable provider prefix in '$MODEL_SPEC' — only openrouter: supported in v1"
    ;;
esac

# ── OpenRouter key (loud-fail if absent; never echo the secret) ─────────────────

if [ -z "${OPENROUTER_API_KEY:-}" ] && [ -n "$KEYSTORE" ]; then
  [ -f "$KEYSTORE" ] || die 4 "keystore not found: $KEYSTORE"
  # shellcheck disable=SC1090
  . "$KEYSTORE"
fi
[ -n "${OPENROUTER_API_KEY:-}" ] || die 4 "OPENROUTER_API_KEY empty or unset; export it or set OPENROUTER_KEYSTORE"

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
    printf '[EXTERNAL-ACTION] model-pass: model=%s bytes_in=%s bytes_out=%s finish_reason=%s status=%s exit=%s ts=%s\n' \
      "$MODEL_SPEC" "$INPUT_BYTES" "$out_bytes" "$finish" "$status" "$exit_code" "$ts" \
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

BODY="$(jq -n \
  --arg model "$MODEL_ID" \
  --argjson max_tokens "$MAX_TOKENS" \
  --argjson temperature "$TEMPERATURE" \
  --rawfile instruction "$INSTRUCTION_FILE" \
  --rawfile draft "$DRAFT_FILE" \
  '{
    model: $model,
    max_tokens: $max_tokens,
    temperature: $temperature,
    messages: [
      {role: "system", content: $instruction},
      {role: "user",   content: ("Improve the following draft:\n\n" + $draft)}
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

# d. non-empty / non-whitespace content
CONTENT="$(printf '%s' "$RESPONSE" | jq -r '.choices[0].message.content // ""' 2>/dev/null || echo "")"
if [ -z "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ]; then
  die_logged 3 "$FINISH_REASON" "0" "model returned empty or whitespace-only content"
fi

# e. length-delta sanity — bytes, integer arithmetic. Reject < 50% or > 300% of input.
#    Write the candidate to a temp file FIRST (this is also the atomic-write staging),
#    measure its byte count, and only mv into place after this final check passes.
OUT_TMP="${OUT_FILE}.tmp.$$"
# Ensure the temp file is removed on any unexpected early exit from here on.
trap 'rm -f "$OUT_TMP"' EXIT
printf '%s' "$CONTENT" > "$OUT_TMP"
OUTPUT_BYTES="$(wc -c < "$OUT_TMP" | tr -d '[:space:]')"

LOWER=$(( INPUT_BYTES * 50 / 100 ))
UPPER=$(( INPUT_BYTES * 300 / 100 ))
if [ "$OUTPUT_BYTES" -lt "$LOWER" ] || [ "$OUTPUT_BYTES" -gt "$UPPER" ]; then
  rm -f "$OUT_TMP"
  die_logged 3 "$FINISH_REASON" "$OUTPUT_BYTES" \
    "length-delta out of range: output ${OUTPUT_BYTES}B vs input ${INPUT_BYTES}B (allowed ${LOWER}B-${UPPER}B); likely a refusal, summary, or runaway"
fi

# ── atomic write — all checks passed; promote the temp file into place ──────────
mv "$OUT_TMP" "$OUT_FILE"
trap - EXIT

log_action "ok" "0" "$FINISH_REASON" "$OUTPUT_BYTES"
exit 0
