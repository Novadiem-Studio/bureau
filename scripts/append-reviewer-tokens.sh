#!/usr/bin/env bash
# append-reviewer-tokens.sh — emit a REVIEWER-TOKEN-EVENT for one cold-reviewer
# spawn (#26b). Called by the Delegate manager after each per-checkpoint
# provider-normalized one-shot reviewer returns.
#
# WHY A HELPER (not an inline LLM-formatted line): the Delegate persona is prose,
# and a hand-formatted token JSON line is exactly the kind of thing that drifts
# (mis-summed processed, wrong key order, missing field). This shell one-shot
# parses the envelope's `.usage` deterministically and appends through the shared
# locked_append mutex, so the emitted line is machine-computed and testable in
# isolation — the same philosophy as log-append.sh.
#
# Each cold reviewer is a FRESH one-shot: its `.usage` is the complete,
# non-cumulative cost of that single spawn, so REVIEWER-TOKEN-EVENT is RAW — no
# baseline/delta machinery. Conductor, Delegate, and specialist figures instead come
# from terminal post-hoc transcript aggregation. Each reviewer spawn is counted exactly once
# via a distinct spawn_id; the rollup (account-tokens.sh) sums across spawn_ids.
#
# Usage:
#   append-reviewer-tokens.sh <RUN_DIR> <checkpoint> <spawn_id> <envelope-json>
#
# Arguments:
#   <RUN_DIR>        absolute run dir (its log.md is the append target)
#   <checkpoint>     checkpoint number NN (bucket key)
#   <spawn_id>       per-spawn discriminator, unique within the run (e.g. "NN-<k>"
#                    where k increments per reviewer spawn at checkpoint NN — a
#                    single checkpoint can spawn the reviewer more than once via
#                    hash-mismatch re-spawn or a revise cycle; each is a distinct
#                    cost and MUST be counted once)
#   <envelope-json>  the full provider-normalized result envelope; its `.usage`
#                    sibling carries Claude-shaped token counts
#
# Exit codes:
#   0  event appended (including the zero-token fail-safe on a missing .usage)
#   1  bad arguments
#
# Fail-safe (mirrors the hooks' zero-token fallback): if the envelope has no
# `.usage` block (older CLI, error envelope), append a zero-token event with a
# _note so a reviewer spawn is NEVER silently uncounted.
#
# Portability: Bash 3.2 + jq on macOS. No GNU-only date flags.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -ne 4 ]; then
  echo "[append-reviewer-tokens] usage: append-reviewer-tokens.sh <RUN_DIR> <checkpoint> <spawn_id> <envelope-json>" >&2
  exit 1
fi

RUN_DIR="$1"
CHECKPOINT="$2"
SPAWN_ID="$3"
ENVELOPE="$4"

if [ -z "$RUN_DIR" ] || [ -z "$CHECKPOINT" ] || [ -z "$SPAWN_ID" ]; then
  echo "[append-reviewer-tokens] RUN_DIR, checkpoint, and spawn_id must all be non-empty" >&2
  exit 1
fi

LOG_MD="$RUN_DIR/log.md"

# shellcheck source=lib/bureau-token-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/bureau-token-lib.sh"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Compose the line. jq extracts .usage (the envelope sibling of .result), maps the
# Claude Code usage field names to the accounting schema, and derives
# processed = input + cache_creation + cache_read (same identity as every other
# token event). A missing/non-object .usage → zero-token event + _note (fail-safe).
# .num_turns is the envelope's turn count for this one-shot (0 if absent).
EVENT_LINE=$(printf '%s' "$ENVELOPE" | jq -c \
  --arg checkpoint "$CHECKPOINT" \
  --arg at "$NOW" \
  --arg spawn_id "$SPAWN_ID" \
  '
  # Absent .usage → null; scalar .usage → null; object .usage → itself. (Note:
  # `.usage | objects` yields EMPTY on absent, which would collapse the whole
  # pipeline — so normalize to an explicit null instead.)
  ((.usage // null) | if type == "object" then . else null end) as $u
  | (.num_turns // 0) as $turns
  | if $u == null then
      {
        checkpoint: $checkpoint,
        at: $at,
        turns: 0,
        tokens: {input:0, cache_creation:0, cache_read:0, processed:0, output:0},
        spawn_id: $spawn_id,
        _note: "reviewer envelope had no .usage block — emitted zero-token event so the spawn is not silently uncounted"
      }
    else
      # B15 (minor): `numbers // 0`, NOT `// 0`. `//` only substitutes on
      # null/false/empty — a STRING field (e.g. "input_tokens":"1234") passes through
      # `// 0` unchanged, then the `$in + $cc + $cr` add throws "string and number
      # cannot be added", the whole per-envelope jq fails, EVENT_LINE goes empty, and
      # the line-116 fallback emits an all-zero event with the WRONG note ("not
      # parseable JSON" — but the envelope WAS parseable), discarding the good sibling
      # fields. `numbers // 0` coerces a non-number field to 0 INLINE: the add never
      # crashes, the good siblings (cache_creation, cache_read, output) survive, and
      # processed is derived correctly. A coerced field is surfaced via _note below
      # instead of being silently zeroed — but the envelope is NOT collapsed.
      ($u.input_tokens                | numbers // 0) as $in  |
      ($u.cache_creation_input_tokens | numbers // 0) as $cc  |
      ($u.cache_read_input_tokens     | numbers // 0) as $cr  |
      ($u.output_tokens               | numbers // 0) as $out |
      # Which of the four usage fields were PRESENT but non-numeric (coerced to 0)?
      ([ (if (($u.input_tokens // null) != null) and (($u.input_tokens | type) != "number") then "input_tokens" else empty end),
         (if (($u.cache_creation_input_tokens // null) != null) and (($u.cache_creation_input_tokens | type) != "number") then "cache_creation_input_tokens" else empty end),
         (if (($u.cache_read_input_tokens // null) != null) and (($u.cache_read_input_tokens | type) != "number") then "cache_read_input_tokens" else empty end),
         (if (($u.output_tokens // null) != null) and (($u.output_tokens | type) != "number") then "output_tokens" else empty end)
       ]) as $coerced |
      ({
        checkpoint: $checkpoint,
        at: $at,
        turns: $turns,
        tokens: {
          input: $in,
          cache_creation: $cc,
          cache_read: $cr,
          processed: ($in + $cc + $cr),
          output: $out
        },
        spawn_id: $spawn_id
      }
      + (if ($coerced | length) > 0
         then {_note: ("non-numeric usage field(s) coerced to zero: " + ($coerced | join(", ")) + " — good sibling fields preserved")}
         else {} end))
    end
  ' 2>/dev/null)

# If jq failed outright (malformed envelope JSON), still emit a zero-token event
# so the spawn is never dropped — compose the fallback line without jq on input.
if [ -z "$EVENT_LINE" ]; then
  EVENT_LINE=$(jq -cn \
    --arg checkpoint "$CHECKPOINT" \
    --arg at "$NOW" \
    --arg spawn_id "$SPAWN_ID" \
    '{
      checkpoint: $checkpoint,
      at: $at,
      turns: 0,
      tokens: {input:0, cache_creation:0, cache_read:0, processed:0, output:0},
      spawn_id: $spawn_id,
      _note: "reviewer envelope was not parseable JSON — emitted zero-token event so the spawn is not silently uncounted"
    }' 2>/dev/null)
fi

if [ -z "$EVENT_LINE" ]; then
  echo "[append-reviewer-tokens] failed to compose REVIEWER-TOKEN-EVENT — nothing appended" >&2
  exit 0
fi

# OWNERSHIP-GATE: none-self — Delegate-driven, caller-attested (no hook self-gate)
locked_append "$LOG_MD" "REVIEWER-TOKEN-EVENT: $EVENT_LINE"
exit 0
