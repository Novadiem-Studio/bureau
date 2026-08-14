#!/usr/bin/env bash
# bureau-token-lib.sh — shared token-accounting library (Bundle 11).
#
# SOURCED ONLY. The post-hoc aggregator uses transcript summation and the
# reviewer-token helper uses locked append; this file must never be executed
# directly.
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

# Shared jq prelude for transcript timestamp windows. ISO-8601 UTC strings are
# not directly comparable when one side includes fractional seconds and the
# other does not ("...01.1Z" sorts before "...01Z"). Parse the whole-second
# component and compare a canonical fractional component so mixed precision
# retains exact half-open boundary semantics without floating-point rounding.
# Non-ISO or absent timestamps retain the prior jq ordering behavior; older
# until-only callers intentionally admit their untimestamped fixture records.
BUREAU_TRANSCRIPT_WINDOW_JQ='
def bureau_iso8601_timestamp_key:
  if type != "string" then null
  else try (
    [capture("^(?<whole>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\\.(?<fraction>[0-9]+))?Z$")]
    | if length == 0 then null
      else .[0]
      | [((.whole + "Z") | fromdateiso8601), ((.fraction // "") | sub("0+$"; ""))]
      end
  ) catch null
  end;
def transcript_timestamp_in_window($timestamp; $since; $until):
  ($timestamp | bureau_iso8601_timestamp_key) as $timestamp_key
  | ($since | bureau_iso8601_timestamp_key) as $since_key
  | ($until | bureau_iso8601_timestamp_key) as $until_key
  | if ($timestamp_key == null)
       or (($since != "") and ($since_key == null))
       or (($until != "") and ($until_key == null))
    then (($since == "") or ($timestamp >= $since))
      and (($until == "") or ($timestamp < $until))
    else (($since == "") or ($timestamp_key >= $since_key))
      and (($until == "") or ($timestamp_key < $until_key))
    end;
'

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
  jq -Rn --arg since "$since_iso" --arg until "$until_iso" "$BUREAU_TRANSCRIPT_WINDOW_JQ"'
    [inputs | fromjson?]
    | (if ($since == "" and $until == "") then .
       else [ .[]
              | select(transcript_timestamp_in_window(.timestamp?; $since; $until))
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
