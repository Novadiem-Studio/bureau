#!/usr/bin/env bash
# aggregate-transcripts.sh — recover per-leg Claude token usage from JSONL transcripts.
#
# Usage: aggregate-transcripts.sh <RUN_DIR> [--until <iso>]
# The --until value is accepted for the prompt-02 windowing extension. This first
# version intentionally sums whole files.

# Step 0: pin system tools ahead of ugrep and other user-installed replacements.
PATH=/usr/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/bureau-token-lib.sh
. "$SCRIPT_DIR/lib/bureau-token-lib.sh"

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "Usage: aggregate-transcripts.sh <RUN_DIR> [--until <iso>]" >&2
  exit 2
fi
shift

UNTIL_ISO=""
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--until" ] || [ -z "$2" ]; then
    echo "Usage: aggregate-transcripts.sh <RUN_DIR> [--until <iso>]" >&2
    exit 2
  fi
  UNTIL_ISO="$2"
fi
# Parsed now for forward compatibility; prompt 02 makes this the transcript window bound.
: "$UNTIL_ISO"

case "$RUN_DIR" in
  /) ;;
  */) RUN_DIR=${RUN_DIR%/} ;;
esac

# The runtime gate deliberately precedes every transcript path resolution/read.
runtime=$(jq -r '.runtime // empty' "$RUN_DIR/model-routing.json" 2>/dev/null)
if [ "$runtime" != "claude" ]; then
  [ -n "$runtime" ] || runtime="unknown"
  jq -cn --arg gap "$runtime — no Claude JSONL; named Codex gap (docs/host-runtime.md)" \
    '{_runtime_gap:$gap}'
  exit 0
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bureau-aggregate.XXXXXX") || {
  echo "aggregate-transcripts: could not create temporary directory" >&2
  exit 1
}
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

ZERO_TOKENS='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0}'
DELEGATE_JSON="$TMP_ROOT/delegate.json"
CONDUCTOR_JSON="$TMP_ROOT/conductor.json"
SPECIALISTS_JSONL="$TMP_ROOT/specialists.jsonl"
ATTEMPTS_TSV="$TMP_ROOT/attempts.tsv"
RECORDED_CONDUCTORS="$TMP_ROOT/recorded-conductors.txt"
DISCOVERED_CONDUCTORS="$TMP_ROOT/discovered-conductors.tsv"
CANDIDATES_TSV="$TMP_ROOT/candidates.tsv"
UNATTRIBUTED_TSV="$TMP_ROOT/unattributed.tsv"
CONDUCTOR_USAGE="$TMP_ROOT/conductor-usage.jsonl"
: > "$SPECIALISTS_JSONL"
: > "$ATTEMPTS_TSV"
: > "$RECORDED_CONDUCTORS"
: > "$DISCOVERED_CONDUCTORS"
: > "$CANDIDATES_TSV"
: > "$UNATTRIBUTED_TSV"
: > "$CONDUCTOR_USAGE"

PROJECTS_ROOT="${BUREAU_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

target_repo=$(jq -r '.target_repo // empty' "$RUN_DIR/state.json" 2>/dev/null)
if [ "$target_repo" = "(no-target)" ] || [ -z "$target_repo" ] || [ "$target_repo" = "$FRAMEWORK_ROOT" ]; then
  target_repo="$FRAMEWORK_ROOT"
fi
M=$(printf '%s' "$target_repo" | sed 's#[/.]#-#g')
EXPECTED_PROJECT_DIR="$PROJECTS_ROOT/$M"

# Same pointer precedence as run-start.sh and spawn-gate.sh.
if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  POINTER_FILE="$BUREAU_POINTER_FILE"
else
  POINTER_DIR="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  POINTER_KEY=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')
  POINTER_FILE="$POINTER_DIR/$POINTER_KEY"
fi
pointer_pair=$(jq -r '[(.nonce // ""), (.written_at // "")] | @tsv' "$POINTER_FILE" 2>/dev/null)
NONCE=$(printf '%s' "$pointer_pair" | awk -F '\t' '{print $1}')
NONCE_WRITTEN_AT=$(printf '%s' "$pointer_pair" | awk -F '\t' '{print $2}')
RUN_STARTED_AT=$(jq -r '.run_started_at // empty' "$RUN_DIR/delegate-state.json" 2>/dev/null)

if [ -n "$RUN_STARTED_AT" ] && [ -n "$NONCE" ] && [ -n "$NONCE_WRITTEN_AT" ] && \
   [ "$(jq -nr --arg written "$NONCE_WRITTEN_AT" --arg started "$RUN_STARTED_AT" '$written <= $started')" = "true" ]; then
  SCOPE_MODE="strict"
  SCOPE_NOTE=""
else
  SCOPE_MODE="legacy"
  if [ -n "$RUN_STARTED_AT" ] && [ -n "$NONCE" ] && [ -n "$NONCE_WRITTEN_AT" ]; then
    SCOPE_NOTE="legacy specialist membership basis: first RUN_DIR header only (nonce postdates run start — rotated)"
  else
    SCOPE_NOTE="legacy specialist membership basis: first RUN_DIR header only (no write-once nonce on this run)"
  fi
fi

# One row per distinct SPAWN-EVENT attempt, preserving first-seen order.
if [ -r "$RUN_DIR/log.md" ]; then
  grep '^SPAWN-EVENT:' "$RUN_DIR/log.md" 2>/dev/null \
    | sed 's/^SPAWN-EVENT:[[:space:]]*//' \
    | jq -Rr 'fromjson? | select((.attempt_id? | type) == "string" and (.attempt_id | length) > 0) | [.attempt_id, (.role // "")] | @tsv' 2>/dev/null \
    | awk -F '\t' '!seen[$1]++' > "$ATTEMPTS_TSV"
fi

json_usage() {
  usage_path="$1"
  usable_count=$(jq -Rn '[inputs | fromjson? | select(.type? == "assistant") | select(.message.id? != null) | select(.message.usage? != null)] | length' "$usage_path" 2>/dev/null)
  if [ -z "$usable_count" ] || [ "$usable_count" -eq 0 ] 2>/dev/null; then
    return 1
  fi
  raw_usage=$(sum_transcript_usage "$usage_path" 2>/dev/null) || return 1
  printf '%s' "$raw_usage" | jq -c '{tokens:{input:.input,cache_creation:.cache_creation,cache_read:.cache_read,processed:.processed,output:.output},turns:.turns}' 2>/dev/null
}

resolve_top_transcript() {
  resolve_sid="$1"
  resolve_expected="$EXPECTED_PROJECT_DIR/$resolve_sid.jsonl"
  if [ -r "$resolve_expected" ]; then
    printf '%s\n' "$resolve_expected"
    return 0
  fi
  resolve_count=0
  resolve_hit=""
  for resolve_candidate in "$PROJECTS_ROOT"/*/"$resolve_sid.jsonl"; do
    [ -r "$resolve_candidate" ] || continue
    resolve_count=$((resolve_count + 1))
    resolve_hit="$resolve_candidate"
  done
  if [ "$resolve_count" -eq 1 ]; then
    printf '%s\n' "$resolve_hit"
    return 0
  fi
  return 1
}

first_run_dir() {
  grep -o 'RUN_DIR: [^\\"]*' "$1" 2>/dev/null | head -1 | sed 's/^RUN_DIR: //'
}

first_attempt_id() {
  grep -o 'Attempt ID: [^\\"]*' "$1" 2>/dev/null | head -1 | sed 's/^Attempt ID: //'
}

is_recorded_conductor() {
  grep -Fqx "$1" "$RECORDED_CONDUCTORS" 2>/dev/null
}

attempt_role() {
  awk -F '\t' -v wanted="$1" '$1 == wanted { print $2; exit }' "$ATTEMPTS_TSV"
}

append_note() {
  if [ -z "$conductor_note" ]; then
    conductor_note="$1"
  else
    conductor_note="$conductor_note; $1"
  fi
}

# Delegate key precedence: delegate-state first, then legacy record read only.
DELEGATE_SESSION_ID=$(jq -r '.delegate_session_id // empty' "$RUN_DIR/delegate-state.json" 2>/dev/null)
if [ -z "$DELEGATE_SESSION_ID" ] && [ -r "$RUN_DIR/log.md" ]; then
  DELEGATE_SESSION_ID=$(grep '^DELEGATE-TOKEN-EVENT:' "$RUN_DIR/log.md" 2>/dev/null \
    | sed 's/^DELEGATE-TOKEN-EVENT:[[:space:]]*//' \
    | jq -Rr 'fromjson? | .session_id? // empty' 2>/dev/null \
    | awk 'NF {print; exit}')
fi

DELEGATE_TRANSCRIPT=""
SESSION_BASE=""
if [ -z "$DELEGATE_SESSION_ID" ]; then
  jq -cn --argjson tokens "$ZERO_TOKENS" \
    --arg note "Delegate session id not recorded at bootstrap — leg not recoverable; record delegate_session_id (FR11) to fix" \
    '{tokens:$tokens,turns:0,confidence:"unavailable",_note:$note}' > "$DELEGATE_JSON"
else
  DELEGATE_TRANSCRIPT=$(resolve_top_transcript "$DELEGATE_SESSION_ID" 2>/dev/null)
  if [ -n "$DELEGATE_TRANSCRIPT" ]; then
    SESSION_BASE=$(dirname "$DELEGATE_TRANSCRIPT")/"$DELEGATE_SESSION_ID"
    delegate_usage=$(json_usage "$DELEGATE_TRANSCRIPT")
    if [ -n "$delegate_usage" ]; then
      printf '%s' "$delegate_usage" | jq -c '. + {confidence:"exact"}' > "$DELEGATE_JSON"
    else
      jq -cn --argjson tokens "$ZERO_TOKENS" \
        --arg note "no usable message.id usage in transcript: $DELEGATE_TRANSCRIPT" \
        '{tokens:$tokens,turns:0,confidence:"unavailable",_note:$note}' > "$DELEGATE_JSON"
    fi
  else
    missing_delegate="$EXPECTED_PROJECT_DIR/$DELEGATE_SESSION_ID.jsonl"
    jq -cn --argjson tokens "$ZERO_TOKENS" --arg note "transcript missing: $missing_delegate" \
      '{tokens:$tokens,turns:0,confidence:"unavailable",_note:$note}' > "$DELEGATE_JSON"
    SESSION_BASE="$EXPECTED_PROJECT_DIR/$DELEGATE_SESSION_ID"
  fi
fi

# A unique top-session directory glob also recovers subagents when the munged cwd guess missed.
if [ -n "$DELEGATE_SESSION_ID" ] && [ ! -d "$SESSION_BASE/subagents" ]; then
  session_dir_count=0
  session_dir_hit=""
  for session_dir_candidate in "$PROJECTS_ROOT"/*/"$DELEGATE_SESSION_ID"; do
    [ -d "$session_dir_candidate/subagents" ] || continue
    session_dir_count=$((session_dir_count + 1))
    session_dir_hit="$session_dir_candidate"
  done
  [ "$session_dir_count" -eq 1 ] && SESSION_BASE="$session_dir_hit"
fi
SUBAGENTS_DIR="$SESSION_BASE/subagents"

# Recorded Conductor ids are append-list union current id, de-duplicated.
jq -r '(.conductor_agent_ids[]? // empty), (.conductor_agent_id // empty) | select(type == "string" and length > 0)' \
  "$RUN_DIR/delegate-state.json" 2>/dev/null | awk '!seen[$0]++' > "$RECORDED_CONDUCTORS"

# Enumerate the session once. Recorded conductors are handled below; discovered
# conductors and specialist candidates are classified here.
excluded_count=0
if [ -d "$SUBAGENTS_DIR" ]; then
  for transcript in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -r "$transcript" ] || continue
    agent_base=$(basename "$transcript")
    agent_id=${agent_base#agent-}
    agent_id=${agent_id%.jsonl}

    if is_recorded_conductor "$agent_id"; then
      continue
    fi

    marker_offset=$(grep -bo 'BUREAU_ROLE: conductor' "$transcript" 2>/dev/null | head -1 | cut -d: -f1)
    attempt_offset=$(grep -bo 'Attempt ID:' "$transcript" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$marker_offset" ] && { [ -z "$attempt_offset" ] || [ "$marker_offset" -lt "$attempt_offset" ]; }; then
      own_run_dir=$(first_run_dir "$transcript")
      if [ "$own_run_dir" = "$RUN_DIR" ]; then
        printf '%s\t%s\n' "$agent_id" "$transcript" >> "$DISCOVERED_CONDUCTORS"
      else
        excluded_count=$((excluded_count + 1))
      fi
      continue
    fi

    own_run_dir=$(first_run_dir "$transcript")
    identity_pass=false
    if [ "$own_run_dir" = "$RUN_DIR" ]; then
      if [ "$SCOPE_MODE" = "legacy" ]; then
        identity_pass=true
      elif grep -Fq "Run nonce: $NONCE" "$transcript" 2>/dev/null; then
        identity_pass=true
      fi
    fi

    if [ "$identity_pass" != "true" ]; then
      excluded_count=$((excluded_count + 1))
      continue
    fi

    candidate_attempt=$(first_attempt_id "$transcript")
    candidate_role=$(attempt_role "$candidate_attempt")
    if [ -n "$candidate_attempt" ] && [ -n "$candidate_role" ]; then
      printf '%s\t%s\t%s\t%s\n' "$candidate_attempt" "$candidate_role" "$agent_id" "$transcript" >> "$CANDIDATES_TSV"
    else
      printf '%s\t%s\n' "$agent_id" "$transcript" >> "$UNATTRIBUTED_TSV"
    fi
  done
fi

if [ "$excluded_count" -gt 0 ]; then
  echo "aggregate-transcripts: excluded $excluded_count sibling/foreign transcript(s) outside this run" >&2
fi

# Conductor leg: every recorded id plus run-scoped discovered conductor markers.
conductor_note=""
recorded_count=$(awk 'NF {n++} END {print n+0}' "$RECORDED_CONDUCTORS")
discovered_count=$(awk 'NF {n++} END {print n+0}' "$DISCOVERED_CONDUCTORS")
conductor_legs=$((recorded_count + discovered_count))
conductor_missing=0
conductor_valid=0

if [ "$recorded_count" -gt 1 ]; then
  respawned_ids=$(tail -n +2 "$RECORDED_CONDUCTORS" | paste -sd ',' -)
  append_note "includes re-spawned conductor id(s): $respawned_ids"
fi

while IFS= read -r conductor_id; do
  [ -n "$conductor_id" ] || continue
  conductor_path="$SUBAGENTS_DIR/agent-$conductor_id.jsonl"
  if [ ! -r "$conductor_path" ]; then
    conductor_missing=$((conductor_missing + 1))
    append_note "transcript missing: $conductor_path"
    continue
  fi
  conductor_one=$(json_usage "$conductor_path")
  if [ -z "$conductor_one" ]; then
    conductor_missing=$((conductor_missing + 1))
    append_note "no usable message.id usage in transcript: $conductor_path"
    continue
  fi
  printf '%s\n' "$conductor_one" >> "$CONDUCTOR_USAGE"
  conductor_valid=$((conductor_valid + 1))
done < "$RECORDED_CONDUCTORS"

discovered_ids=""
while IFS="$(printf '\t')" read -r conductor_id conductor_path; do
  [ -n "$conductor_id" ] || continue
  conductor_one=$(json_usage "$conductor_path")
  if [ -z "$conductor_one" ]; then
    conductor_missing=$((conductor_missing + 1))
    append_note "no usable message.id usage in transcript: $conductor_path"
    continue
  fi
  printf '%s\n' "$conductor_one" >> "$CONDUCTOR_USAGE"
  conductor_valid=$((conductor_valid + 1))
  if [ -z "$discovered_ids" ]; then discovered_ids="$conductor_id"; else discovered_ids="$discovered_ids,$conductor_id"; fi
done < "$DISCOVERED_CONDUCTORS"

if [ -n "$discovered_ids" ]; then
  append_note "includes unrecorded conductor-marked leg(s) $discovered_ids — record conductor ids (delegate-state.json#conductor_agent_ids) for exact"
fi

if [ "$conductor_valid" -gt 0 ]; then
  conductor_totals=$(jq -cs '{tokens:{input:(map(.tokens.input)|add//0),cache_creation:(map(.tokens.cache_creation)|add//0),cache_read:(map(.tokens.cache_read)|add//0),processed:(map(.tokens.processed)|add//0),output:(map(.tokens.output)|add//0)},turns:(map(.turns)|add//0)}' "$CONDUCTOR_USAGE")
  conductor_confidence="exact"
  [ "$conductor_missing" -eq 0 ] && [ "$discovered_count" -eq 0 ] || conductor_confidence="partial"
  if [ -n "$conductor_note" ]; then
    printf '%s' "$conductor_totals" | jq -c --argjson legs "$conductor_legs" --arg confidence "$conductor_confidence" --arg note "$conductor_note" \
      '. + {legs:$legs,confidence:$confidence,_note:$note}' > "$CONDUCTOR_JSON"
  else
    printf '%s' "$conductor_totals" | jq -c --argjson legs "$conductor_legs" --arg confidence "$conductor_confidence" \
      '. + {legs:$legs,confidence:$confidence}' > "$CONDUCTOR_JSON"
  fi
else
  if [ "$conductor_legs" -eq 0 ]; then
    conductor_note="Conductor agent id not recorded — leg not recoverable; record conductor_agent_ids in delegate-state.json to fix"
  elif [ -z "$conductor_note" ]; then
    conductor_note="no usable Conductor transcript resolved"
  fi
  jq -cn --argjson tokens "$ZERO_TOKENS" --argjson legs "$conductor_legs" --arg note "$conductor_note" \
    '{tokens:$tokens,turns:0,legs:$legs,confidence:"unavailable",_note:$note}' > "$CONDUCTOR_JSON"
fi

# Emit one record per SPAWN-EVENT attempt in event order.
while IFS="$(printf '\t')" read -r attempt_id role; do
  [ -n "$attempt_id" ] || continue
  candidate_count=$(awk -F '\t' -v wanted="$attempt_id" '$1 == wanted {n++} END {print n+0}' "$CANDIDATES_TSV")
  if [ "$candidate_count" -eq 0 ]; then
    jq -cn --arg attempt "$attempt_id" --arg role "$role" --argjson tokens "$ZERO_TOKENS" \
      '{attempt_id:$attempt,role:$role,agent_id:null,tokens:$tokens,turns:0,confidence:"unavailable",_note:"no run-scoped transcript resolved for this SPAWN-EVENT attempt"}' \
      >> "$SPECIALISTS_JSONL"
  elif [ "$candidate_count" -gt 1 ]; then
    claiming_ids=$(awk -F '\t' -v wanted="$attempt_id" '$1 == wanted {print $3}' "$CANDIDATES_TSV" | sort -u | paste -sd ',' -)
    jq -cn --arg attempt "$attempt_id" --arg role "$role" --argjson tokens "$ZERO_TOKENS" \
      --arg note "attempt-id collision after run-scoping: $claiming_ids — not summed (over-count guard)" \
      '{attempt_id:$attempt,role:$role,agent_id:null,tokens:$tokens,turns:0,confidence:"suspect",_note:$note}' \
      >> "$SPECIALISTS_JSONL"
  else
    candidate_row=$(awk -F '\t' -v wanted="$attempt_id" '$1 == wanted {print; exit}' "$CANDIDATES_TSV")
    candidate_agent=$(printf '%s' "$candidate_row" | awk -F '\t' '{print $3}')
    candidate_path=$(printf '%s' "$candidate_row" | awk -F '\t' '{print $4}')
    candidate_usage=$(json_usage "$candidate_path")
    if [ -n "$candidate_usage" ]; then
      printf '%s' "$candidate_usage" | jq -c --arg attempt "$attempt_id" --arg role "$role" --arg agent "$candidate_agent" \
        '. + {attempt_id:$attempt,role:$role,agent_id:$agent,confidence:"exact"}' \
        | jq -c '{attempt_id,role,agent_id,tokens,turns,confidence}' >> "$SPECIALISTS_JSONL"
    else
      jq -cn --arg attempt "$attempt_id" --arg role "$role" --arg agent "$candidate_agent" --argjson tokens "$ZERO_TOKENS" \
        --arg note "no usable message.id usage in transcript: $candidate_path" \
        '{attempt_id:$attempt,role:$role,agent_id:$agent,tokens:$tokens,turns:0,confidence:"unavailable",_note:$note}' \
        >> "$SPECIALISTS_JSONL"
    fi
  fi
done < "$ATTEMPTS_TSV"

# Run-scoped transcripts without SPAWN-EVENT membership are real cost, emitted once.
while IFS="$(printf '\t')" read -r candidate_agent candidate_path; do
  [ -n "$candidate_agent" ] || continue
  candidate_usage=$(json_usage "$candidate_path")
  if [ -n "$candidate_usage" ]; then
    printf '%s' "$candidate_usage" | jq -c --arg agent "$candidate_agent" \
      '. + {attempt_id:null,role:null,agent_id:$agent,confidence:"inferred",_note:"run-scoped transcript has no matching SPAWN-EVENT; summed as unattributed"}' \
      | jq -c '{attempt_id,role,agent_id,tokens,turns,confidence,_note}' >> "$SPECIALISTS_JSONL"
  else
    jq -cn --arg agent "$candidate_agent" --argjson tokens "$ZERO_TOKENS" --arg note "no usable message.id usage in transcript: $candidate_path" \
      '{attempt_id:null,role:null,agent_id:$agent,tokens:$tokens,turns:0,confidence:"unavailable",_note:$note}' \
      >> "$SPECIALISTS_JSONL"
  fi
done < "$UNATTRIBUTED_TSV"

if [ "$SCOPE_MODE" = "legacy" ]; then
  jq -cn --slurpfile delegate "$DELEGATE_JSON" --slurpfile conductor "$CONDUCTOR_JSON" \
    --slurpfile specialists "$SPECIALISTS_JSONL" --arg scope_note "$SCOPE_NOTE" \
    '{delegate:$delegate[0],conductor:$conductor[0],specialists:$specialists,_scope_note:$scope_note}'
else
  jq -cn --slurpfile delegate "$DELEGATE_JSON" --slurpfile conductor "$CONDUCTOR_JSON" \
    --slurpfile specialists "$SPECIALISTS_JSONL" \
    '{delegate:$delegate[0],conductor:$conductor[0],specialists:$specialists}'
fi

exit 0
