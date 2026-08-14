#!/usr/bin/env bash
# bureau-token-lib.sh — shared token-accounting library (Bundle 11).
#
# SOURCED ONLY. This file is sourced by scripts/subagent-stop.sh and
# scripts/conductor-stop.sh; it must never be executed directly.
#
# Portability: Bash 3.2 + jq on macOS. No associative arrays, no GNU-only
# date flags. Time arithmetic happens in jq via fromdateiso8601.
#
# Field-name ground truth: docs/run-accounting.md § "Hook field names
# (Bundle 11 ground truth)".

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "[bureau-token-lib] this file is a library — source it, do not execute it" >&2
  exit 1
fi

# sum_transcript_usage <jsonl_path> [since_iso] [until_iso]
#
# Reads a Claude Code JSONL transcript, dedups assistant lines on message.id
# (each assistant turn writes one JSONL line per content block, every line
# carrying the identical cumulative message-level usage object — summing
# naively across those repeated lines is the known overcount), and emits one
# compact JSON object on stdout:
#
#   {"input":<n>,"cache_creation":<n>,"cache_read":<n>,"processed":<n>,"output":<n>,"turns":<n>}
#
# processed == input + cache_creation + cache_read (by construction).
# turns == number of deduped message groups containing at least one
# content block of type "tool_use" (checked across every line in the
# group, since the real transcript splits content blocks across lines).
#
# Returns 1 with a message on stderr when the file is not readable.
# (return, not exit — a sourced function must never kill the calling hook.)
sum_transcript_usage() {
  local jsonl_path="$1"
  local since_iso="${2:-}"
  local until_iso="${3:-}"
  if [ -z "$jsonl_path" ] || [ ! -r "$jsonl_path" ]; then
    echo "[bureau-token-lib] sum_transcript_usage: file not readable: ${jsonl_path:-<missing argument>}" >&2
    return 1
  fi
  # -Rn: read each line as a raw string (no JSON parse on import), then
  # fromjson? per line — malformed/truncated lines are silently skipped.
  # Output shape and message.id dedup semantics are identical to the prior
  # -cs implementation; the only difference is line-level fault tolerance.
  jq -Rn --arg since "$since_iso" --arg until "$until_iso" '
    [inputs | fromjson?]
    | (if ($since == "" and $until == "") then .
       else [ .[]
              | select(($since == "" or .timestamp >= $since) and
                       ($until == "" or .timestamp < $until))
            ]
       end)
    | [ .[]
        | select(.type? == "assistant")
        | select(.message.id? != null)
        | select(.message.usage? != null)
      ]
    | group_by(.message.id)
    | {
        input:          (map(.[0].message.usage.input_tokens // 0) | add // 0),
        cache_creation: (map(.[0].message.usage.cache_creation_input_tokens // 0) | add // 0),
        cache_read:     (map(.[0].message.usage.cache_read_input_tokens // 0) | add // 0),
        output:         (map(.[0].message.usage.output_tokens // 0) | add // 0),
        turns:          (map(select(any(.[]; [.message.content[]? | select(.type? == "tool_use")] | length > 0))) | length)
      }
    | { input: .input,
        cache_creation: .cache_creation,
        cache_read: .cache_read,
        processed: (.input + .cache_creation + .cache_read),
        output: .output,
        turns: .turns }
  ' "$jsonl_path"
}

# ── Shared CONDUCTOR-TOKEN-EVENT composition (delta/clamp/processed-identity) ──
#
# One source of truth for the baseline-relative delta arithmetic, shared by both
# emitters that produce CONDUCTOR-TOKEN-EVENT lines:
#   - conductor-stop.sh   (top-session Conductor, baseline in the pointer file)
#   - subagent-stop.sh    (subagent Conductor, baseline in the per-agent dotfile)
#
# The arithmetic (per-field subtract, clamp >= 0, re-derive processed from the
# CLAMPED components, clamp-note wording) is the single most drift-sensitive part
# of the accounting layer, so it lives here once. The STORE machinery (pointer vs
# dotfile read/write, the state machine that decides which baseline applies) stays
# in each caller — only the composed line's math is shared. The extracted jq is a
# byte-for-byte move of conductor-stop.sh's Step F branches (legacy + non-legacy);
# the conductor-stop fixtures (94 legacy, 92/93/95/96/99 delta) are the regression
# proof that this extraction did not change its output.

# compute_legacy_line <usage_json> <session_id> <at> <final_bool>
#
# The pre-Bundle-16 6-key shape (no baseline key, no _note). Emitted when there is
# no baseline to subtract (legacy pointer, or the EC-3 write-fail degrade). Echoes
# one compact JSON object on stdout; empty on jq failure. Byte-identical to the
# legacy branch conductor-stop.sh shipped before this extraction.
compute_legacy_line() {
  local usage_json="$1" session_id="$2" at="$3" final="$4"
  printf '%s' "$usage_json" | jq -c \
    --arg session_id "$session_id" \
    --arg at "$at" \
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
    }' 2>/dev/null
}

# compute_delta_line <usage_json> <session_id> <at> <final_bool> \
#                    <b_input> <b_cache_creation> <b_cache_read> <b_output> \
#                    <b_turns> <baseline_obj_json>
#
# The non-legacy branch: subtract the baseline per field from the raw cumulative,
# clamp each delta >= 0, re-derive processed from the CLAMPED components (never
# clamp processed on its own so the processed == input+cache_creation+cache_read
# identity holds), attach the baseline object and, if any field clamped, a _note
# naming each clamped field with its raw/baseline pair. Key order:
# session_id, at, turns, tokens, final, baseline, then _note last (clamp only).
# Echoes one compact JSON object on stdout; empty on jq failure.
#
# `session_id` is the id VALUE the emitter chose: conductor-stop passes the
# top-session session_id; subagent-stop passes the subagent agent_id. The emitted
# key is literally `session_id` for both, so account-tokens.sh's dedup-by-
# session_id take-max is unchanged for both callers (no consumer change).
compute_delta_line() {
  local usage_json="$1" session_id="$2" at="$3" final="$4"
  local b_input="$5" b_cache_creation="$6" b_cache_read="$7" b_output="$8"
  local b_turns="$9" baseline_obj_json="${10}"
  printf '%s' "$usage_json" | jq -c \
    --arg session_id "$session_id" \
    --arg at "$at" \
    --argjson final "$final" \
    --argjson b_input "$b_input" \
    --argjson b_cache_creation "$b_cache_creation" \
    --argjson b_cache_read "$b_cache_read" \
    --argjson b_output "$b_output" \
    --argjson b_turns "$b_turns" \
    --argjson baseline "$baseline_obj_json" \
    '
    (.input          - $b_input)          as $raw_input          |
    (.cache_creation - $b_cache_creation) as $raw_cache_creation |
    (.cache_read     - $b_cache_read)     as $raw_cache_read     |
    (.output         - $b_output)         as $raw_output         |
    (.turns          - $b_turns)          as $raw_turns          |
    (if $raw_input          < 0 then 0 else $raw_input          end) as $c_input          |
    (if $raw_cache_creation < 0 then 0 else $raw_cache_creation end) as $c_cache_creation |
    (if $raw_cache_read     < 0 then 0 else $raw_cache_read     end) as $c_cache_read     |
    (if $raw_output         < 0 then 0 else $raw_output         end) as $c_output         |
    (if $raw_turns          < 0 then 0 else $raw_turns          end) as $c_turns          |
    ($c_input + $c_cache_creation + $c_cache_read) as $c_processed |
    ([ (if $raw_input          < 0 then "clamped input (raw \(.input) < baseline \($b_input)) to 0" else empty end),
       (if $raw_cache_creation < 0 then "clamped cache_creation (raw \(.cache_creation) < baseline \($b_cache_creation)) to 0" else empty end),
       (if $raw_cache_read     < 0 then "clamped cache_read (raw \(.cache_read) < baseline \($b_cache_read)) to 0" else empty end),
       (if $raw_output         < 0 then "clamped output (raw \(.output) < baseline \($b_output)) to 0" else empty end),
       (if $raw_turns          < 0 then "clamped turns (raw \(.turns) < baseline \($b_turns)) to 0" else empty end)
     ]) as $notes |
    {
      session_id: $session_id,
      at: $at,
      turns: $c_turns,
      tokens: {
        input: $c_input,
        cache_creation: $c_cache_creation,
        cache_read: $c_cache_read,
        processed: $c_processed,
        output: $c_output
      },
      final: $final,
      baseline: $baseline
    }
    + (if ($notes | length) > 0 then {"_note": ($notes | join("; "))} else {} end)
    ' 2>/dev/null
}

# locked_append <logfile> <line>
#
# Atomic single-line append guarded by a mkdir mutex at "<logfile>.lock"
# (macOS ships no file-locking CLI usable here; mkdir is atomic on all
# POSIX filesystems). JSON event lines exceed 512 bytes, so O_APPEND alone
# does not guarantee an uninterrupted line — hence the mutex.
#
# Acquisition: up to 5 mkdir attempts, 0.1 s apart. On acquisition the
# append runs in a subshell whose EXIT trap releases the lock, so the lock
# is released even if the append is interrupted. If the lock cannot be
# acquired within the retry budget: best-effort unlocked append plus a
# warning on stderr — never a hard exit, the calling hook must survive.
locked_append() {
  local logfile="$1"
  local line="$2"
  local lockdir="${logfile}.lock"
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    if mkdir "$lockdir" 2>/dev/null; then
      (
        trap 'rmdir "$lockdir" 2>/dev/null' EXIT
        printf '%s\n' "$line" >> "$logfile"
      )
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 0.1
  done
  echo "[bureau-token-lib] locked_append: could not acquire ${lockdir} after 5 attempts — falling back to unlocked append" >&2
  printf '%s\n' "$line" >> "$logfile"
  return 0
}
