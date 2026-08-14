#!/usr/bin/env bash
# account-tokens.sh <RUN_DIR> [posthoc_fragment_path]
#
# Reads run-local narrative events for non-token derivations and the optional
# post-hoc fragment for derived token metrics. It never reads transcripts and no
# longer ingests CONDUCTOR/DELEGATE/SPAWN-TOKEN-EVENT lines (FR4=A REPLACE).
# REVIEWER-TOKEN-EVENT remains live and is intentionally out of REPLACE.

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "[account-tokens] usage: account-tokens.sh <RUN_DIR> [posthoc_fragment_path]" >&2
  exit 2
fi

POSTHOC_FRAGMENT="${2:-}"
posthoc_delegate_identity_present=false
if jq -e '(.delegate_session_id | type) == "string" and (.delegate_session_id | length) > 0' \
     "$RUN_DIR/delegate-state.json" >/dev/null 2>&1; then
  posthoc_delegate_identity_present=true
elif [ -r "$RUN_DIR/log.md" ] && \
     sed -n 's/^DELEGATE-TOKEN-EVENT: //p' "$RUN_DIR/log.md" 2>/dev/null \
       | jq -Rse '
           split("\n")
           | any(.[];
               (try fromjson catch null) as $event
               | (($event | type) == "object")
                 and (($event.session_id | type) == "string")
                 and (($event.session_id | length) > 0))
         ' >/dev/null 2>&1; then
  posthoc_delegate_identity_present=true
fi
posthoc_recorded_conductor_legs=0
if [ -r "$RUN_DIR/delegate-state.json" ]; then
  posthoc_recorded_conductor_legs=$(jq -r '
    [ ((if (.conductor_agent_ids | type) == "array"
          then .conductor_agent_ids[] else empty end)),
      (if (.conductor_agent_id | type) == "string"
       then .conductor_agent_id else empty end) ]
    | map(select(type == "string" and length > 0)) | unique | length
  ' "$RUN_DIR/delegate-state.json" 2>/dev/null || echo 0)
  [ -n "$posthoc_recorded_conductor_legs" ] || posthoc_recorded_conductor_legs=0
fi
posthoc_expected_attempts_json='[]'
if [ -r "$RUN_DIR/log.md" ]; then
  posthoc_expected_attempts_json=$(sed -n 's/^SPAWN-EVENT: //p' "$RUN_DIR/log.md" 2>/dev/null \
    | jq -Rsc '
        def payload_attempt_id:
          (try fromjson catch null) as $json
          | if (($json | type) == "object")
               and (($json.attempt_id | type) == "string")
               and (($json.attempt_id | length) > 0)
            then $json.attempt_id
            else (try capture("(^|[[:space:]])attempt_id=(?<id>[^[:space:]]+)").id
                  catch empty)
            end;
        split("\n")
        | map(select(length > 0) | payload_attempt_id)
        | map(select(type == "string" and length > 0))
        | unique
      ' 2>/dev/null || printf '[]')
  [ -n "$posthoc_expected_attempts_json" ] || posthoc_expected_attempts_json='[]'
fi
posthoc_json="null"
if [ -n "$POSTHOC_FRAGMENT" ] && [ -r "$POSTHOC_FRAGMENT" ] && \
   jq -se --argjson expected_attempts "$posthoc_expected_attempts_json" \
          --argjson recorded_conductor_legs "$posthoc_recorded_conductor_legs" \
          --argjson delegate_identity_present "$posthoc_delegate_identity_present" '
          def nonnegative_number: type == "number" and . >= 0;
          def nonnegative_integer: nonnegative_number and . == floor;
          def role_alias($role):
            if $role == "critic" then "challenger"
            elif $role == "challenger" then "critic"
            elif $role == "designer" then "cleric"
            elif $role == "cleric" then "designer"
            elif $role == "prompt-engineer" then "spellwright"
            elif $role == "spellwright" then "prompt-engineer"
            elif $role == "backend" then "systemsmith"
            elif $role == "systemsmith" then "backend"
            elif $role == "frontend" then "mage"
            elif $role == "mage" then "frontend"
            elif $role == "sysadmin" then "mechanic"
            elif $role == "mechanic" then "sysadmin"
            elif $role == "voice" then "counselor"
            elif $role == "counselor" then "voice"
            else null end;
          def prefixed_attempt($attempt; $prefix):
            ($attempt | startswith($prefix + "-"))
            and (($attempt | length) > (($prefix | length) + 1));
          def confidence_shape:
            . as $confidence
            | (($confidence | type) == "string")
              and (["exact","estimated","partial","unavailable","inferred","suspect"]
                   | index($confidence)) != null;
          def tokens_shape:
            . as $tokens
            | (($tokens | type) == "object")
              and all(["input","cache_creation","cache_read","processed","output"][];
                . as $key
                | ($tokens | has($key))
                  and ($tokens[$key] | nonnegative_number))
              and ($tokens.processed ==
                   ($tokens.input + $tokens.cache_creation + $tokens.cache_read));
          def leg_shape:
            type == "object"
            and (.tokens | tokens_shape)
            and (.turns | nonnegative_integer)
            and (.confidence | confidence_shape);
          def documented_note:
            (._note | type) == "string" and (._note | length) > 0;
          def zero_usage:
            .turns == 0
            and (.tokens
              | .input == 0 and .cache_creation == 0 and .cache_read == 0
                and .processed == 0 and .output == 0);
          def top_leg_shape:
            leg_shape
            and (.confidence == "exact" or .confidence == "partial"
                 or .confidence == "unavailable")
            and (if .confidence == "exact" then true else documented_note end)
            and (if .confidence == "unavailable" then zero_usage else true end);
          def specialist_shape:
            leg_shape
            and has("attempt_id") and has("role") and has("agent_id")
            and (if ((.attempt_id | type) == "string") and ((.attempt_id | length) > 0)
                 then ((.role | type) == "string") and ((.role | length) > 0)
                      and (.attempt_id as $attempt
                        | .role as $role
                        | prefixed_attempt($attempt; $role)
                          or (role_alias($role) as $alias
                            | $alias != null and prefixed_attempt($attempt; $alias)))
                      and (if (.agent_id | type) == "string"
                           then (.agent_id | length) > 0
                                and (.confidence == "exact" or .confidence == "partial"
                                     or .confidence == "unavailable")
                                and (if .confidence == "exact" then true else documented_note end)
                                and (if .confidence == "unavailable" then zero_usage else true end)
                           elif .agent_id == null
                           then (.confidence == "unavailable" or .confidence == "suspect")
                                and documented_note and zero_usage
                           else false end)
                 elif .attempt_id == null
                 then .role == null
                      and ((.agent_id | type) == "string") and ((.agent_id | length) > 0)
                      and (.confidence == "inferred" or .confidence == "partial"
                           or .confidence == "unavailable")
                      and documented_note
                      and (if .confidence == "unavailable" then zero_usage else true end)
                 else false end);
          length == 1
          and (.[0]
            | type == "object"
            and (has("_runtime_gap") | not)
            and (.delegate
              | top_leg_shape
              and (if .confidence == "exact" or .confidence == "partial"
                   then $delegate_identity_present else true end))
            and (.conductor
              | top_leg_shape
              and (.legs | nonnegative_integer)
              and (.legs >= $recorded_conductor_legs)
              and (if .confidence == "exact"
                   then $recorded_conductor_legs > 0
                        and .legs == $recorded_conductor_legs
                   elif .confidence == "partial" then .legs > 0
                   else true end))
            and ((.specialists | type) == "array")
            and all(.specialists[]; specialist_shape)
            and ([.specialists[] | select(.attempt_id != null) | .attempt_id] as $attempt_ids
              | (($attempt_ids | length) == ($attempt_ids | unique | length))
                and (($attempt_ids | unique | sort) == ($expected_attempts | sort)))
            and ([.specialists[] | select(.agent_id != null) | .agent_id] as $agent_ids
              | ($agent_ids | length) == ($agent_ids | unique | length)))' \
      "$POSTHOC_FRAGMENT" >/dev/null 2>&1; then
  posthoc_json=$(jq -c '.' "$POSTHOC_FRAGMENT" 2>/dev/null) || posthoc_json="null"
  [ -n "$posthoc_json" ] || posthoc_json="null"
fi

LOG_MD="$RUN_DIR/log.md"
STATE_JSON="$RUN_DIR/state.json"
DELEGATE_STATE_JSON="$RUN_DIR/delegate-state.json"

tmpd=$(mktemp -d "${TMPDIR:-/tmp}/account-tokens.XXXXXX") || {
  echo "[account-tokens] mktemp failed" >&2
  exit 1
}
trap 'rm -rf "$tmpd"' EXIT

se_f="$tmpd/spawn_events.jsonl"; : > "$se_f"
rv_f="$tmpd/reviewers.jsonl";    : > "$rv_f"
cp_f="$tmpd/checkpoints.jsonl";  : > "$cp_f"
nt_f="$tmpd/notes.jsonl";        : > "$nt_f"

lineno=0
if [ -r "$LOG_MD" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in
      "SPAWN-EVENT: "*)
        prefix="SPAWN-EVENT"; dest="$se_f"; payload="${line#SPAWN-EVENT: }" ;;
      "REVIEWER-TOKEN-EVENT: "*)
        prefix="REVIEWER-TOKEN-EVENT"; dest="$rv_f"; payload="${line#REVIEWER-TOKEN-EVENT: }" ;;
      "CHECKPOINT-EVENT: "*)
        prefix="CHECKPOINT-EVENT"; dest="$cp_f"; payload="${line#CHECKPOINT-EVENT: }" ;;
      *) continue ;;
    esac
    if printf '%s' "$payload" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
      printf '%s\n' "$payload" >> "$dest"
    else
      jq -cn --arg n "line ${lineno}: unparseable ${prefix} payload — skipped (torn or malformed JSON)" '$n' >> "$nt_f"
    fi
  done < "$LOG_MD"
fi

critic_loops_json="null"
if [ -r "$STATE_JSON" ]; then
  critic_loops_json=$(jq -c 'if (.critic_loops | type) == "object" then .critic_loops else null end' "$STATE_JSON" 2>/dev/null) || critic_loops_json="null"
fi

delegate_topology=""
if [ -r "$DELEGATE_STATE_JSON" ]; then
  delegate_topology=$(jq -r 'if (.topology | type) == "string" then .topology else "" end' "$DELEGATE_STATE_JSON" 2>/dev/null) || delegate_topology=""
fi

JQ_PROG=$(cat <<'JQ'
def tsnum: if type == "string" then (try fromdateiso8601 catch null) else null end;
def n: if type == "number" then . else 0 end;
def token_shape:
  (.tokens // null) as $raw
  | {
      input: (($raw.input // 0) | n),
      cache_creation: (($raw.cache_creation // 0) | n),
      cache_read: (($raw.cache_read // 0) | n),
      output: (($raw.output // 0) | n)
    }
  | . + {processed: (.input + .cache_creation + .cache_read)};
def zero_tokens: {input:0,cache_creation:0,cache_read:0,processed:0,output:0};

($spawn_events | to_entries | map(
  .key as $ord | .value
  | . + {attempt_id:
      (if (.attempt_id | type) == "string" and .attempt_id != "" then .attempt_id
       else "__malformed__attempt_id__\($ord)" end)}
)) as $spawn_events
| ($spawn_events | map(select(.status == "started")) | group_by(.attempt_id) | map(.[0])) as $started
| ($spawn_events | map(select(.status == "complete" or .status == "no-handoff" or .status == "failed" or .status == "terminated"))) as $terminals
| ($started | map(
    . as $s
    | ($terminals | map(select(.attempt_id == $s.attempt_id)) | .[0]) as $t
    | ($s.at | tsnum) as $sn
    | (($t.at) | tsnum) as $tn
    | (if $t == null or $sn == null or $tn == null then null else ($tn - $sn) end) as $dur
    | {
        attempt_id: $s.attempt_id,
        rework: ($s.rework // false),
        started_at: $s.at,
        at: (if $t != null then $t.at else $s.at end),
        dur_value: $dur,
        dur_conf: (if $t != null and $sn != null and $tn != null then "exact" else "unavailable" end),
        dur_note: (if $dur != null and $dur <= 0 then "duration_s <= 0 — emitted as-is (clock skew or identical timestamps), not corrected or discarded" else null end)
      }
  )) as $pairs
| ($pairs | map(select(.dur_conf == "exact")) | map(.dur_value) | add // 0) as $active_time
| ($pairs | map(.dur_conf == "exact") | all) as $active_all_exact
| ([ $pairs[] | (.started_at | tsnum), (.at | tsnum) ] | map(select(. != null))) as $narr_ts
| (($narr_ts | length) >= 2 and ($narr_ts | map(. % 3600 == 0) | all)) as $round_hour_fabricated
| (if ($active_all_exact | not) then "partial"
   elif $round_hour_fabricated then "suspect"
   else "exact" end) as $active_conf
| (if $round_hour_fabricated
   then "active_spawn_time_s: all \($narr_ts | length) narrative SPAWN-EVENT timestamps land exactly on the round hour (:00:00) — treated as fabricated (LLM-typed), not exact"
   else null end) as $active_note

| ($reviewers | to_entries | map(
    .key as $ord | .value
    | (.spawn_id | type) as $id_type
    | (.tokens | type) as $tokens_type
    | token_shape as $tk
    | {
        spawn_id: (if $id_type == "string" and .spawn_id != "" then .spawn_id else "__malformed__spawn_id__\($ord)" end),
        tokens: $tk,
        turns: ((.turns // 0) | n),
        _note: (._note // null),
        _isolated: (($id_type != "string") or (.spawn_id == "") or ($tokens_type != "object"))
      }
  )) as $reviewers
| ($reviewers | group_by(.spawn_id) | map(max_by(.tokens.processed))) as $rev
| ($rev | map(.tokens.input) | add // 0) as $rev_input
| ($rev | map(.tokens.cache_creation) | add // 0) as $rev_cc
| ($rev | map(.tokens.cache_read) | add // 0) as $rev_cr
| ($rev | map(.tokens.processed) | add // 0) as $rev_processed
| ($rev | map(.tokens.output) | add // 0) as $rev_output
| ($rev | map(.turns) | add // 0) as $rev_turns
| ($rev | map(._note // empty) | if length > 0 then join("; ") else null end) as $rev_event_notes
| (($rev | map(select(._isolated)) | length) > 0) as $rev_isolated
| (($rev_processed == 0) and ($rev_event_notes != null)) as $rev_zero_with_note
| (if ($rev | length) == 0 then "unavailable"
   elif $rev_isolated or $rev_zero_with_note then "partial"
   else "exact" end) as $rev_conf
| (if ($rev | length) == 0 then "no REVIEWER-TOKEN-EVENT lines present in log.md yet"
   elif $rev_isolated then "one or more reviewer record(s) had a malformed/absent spawn_id or tokens object — isolated, block not blessed as exact"
   elif $rev_zero_with_note then "reviewer block rolled up to zero tokens but at least one event carried a _note — not blessed as exact"
   else $rev_event_notes end) as $rev_block_note

| (if $posthoc == null then 0 else (($posthoc.specialists // []) | map(.tokens.processed // 0) | add // 0) end) as $spec_processed
| (if $posthoc == null then 0 else (($posthoc.specialists // []) | map(.tokens.output // 0) | add // 0) end) as $spec_output
| (if $posthoc == null then 0 else ($posthoc.conductor.tokens.processed // 0) end) as $cond_processed
| (if $posthoc == null then 0 else ($posthoc.conductor.tokens.output // 0) end) as $cond_output
| (if $posthoc == null then 0 else ($posthoc.delegate.tokens.output // 0) end) as $del_output
| ($spec_processed + $cond_processed) as $processed_total
| (if $posthoc == null then "unavailable"
   elif (($posthoc.conductor.confidence // "unavailable") == "exact")
        and (($posthoc.specialists // []) | all((.confidence // "unavailable") == "exact"))
   then "exact" else "partial" end) as $pt_conf
| (if $posthoc == null
   then ["no post-hoc aggregator fragment — per-leg source unavailable"]
   else ([
      (if (($posthoc.conductor.confidence // "unavailable") != "exact")
       then "post-hoc conductor=\($posthoc.conductor.confidence // "unavailable")" else empty end),
      (($posthoc.specialists // [])[]
       | select((.confidence // "unavailable") != "exact")
       | "post-hoc specialist \(.attempt_id // ("unattributed:" + (.agent_id // "unknown")))=\(.confidence // "unavailable")")
   ]) end) as $pt_notes
| ($pairs | map(select(.rework == true) | .attempt_id)) as $rework_ids
| (if $posthoc == null then 0 else ([ $rework_ids[] as $rid
     | (($posthoc.specialists // [])
        | map(select(.attempt_id == $rid))
        | map(.tokens.processed // 0) | max // 0)
   ] | add // 0) end) as $rework_processed
| (if ($critic_loops | type) == "object"
   then ([$critic_loops[]] | map(select(type == "number")) | add // 0)
   else 0 end) as $total_loops

| ($checkpoints | to_entries | map(
    .key as $ord | .value
    | . + {id:(if (.id | type) == "string" and .id != "" then .id else "__malformed__id__\($ord)" end)}
  )) as $checkpoints
| ($checkpoints | map(select(.status == "raised")) | group_by(.id) | map(.[0])) as $raised
| ($checkpoints | map(select(.status == "resolved"))) as $resolved
| ($raised | map(
    . as $r
    | ($resolved | map(select(.id == $r.id)) | .[0]) as $res
    | ($r.at | tsnum) as $rn
    | (($res.at) | tsnum) as $vn
    | (if $res == null or $rn == null or $vn == null then null else ($vn - $rn) end) as $wait
    | {
        id:$r.id, raised_at:$r.at,
        resolved_at:(if $res != null then $res.at else null end),
        decision:(if $res != null then ($res.decision // null) else null end),
        wait_value:$wait,
        wait_conf:(if $res != null and $rn != null and $vn != null then "exact" else "unavailable" end),
        wait_note:(if $wait != null and $wait <= 0 then "wait_s <= 0 — emitted as-is, not corrected or discarded" else null end)
      }
  )) as $cps
| ($cps | map(select(.wait_conf == "exact")) | map(.wait_value) | add // 0) as $human_wait
| ($cps | map(.wait_conf == "exact") | all) as $cp_all_resolved
| (if $cp_all_resolved then "exact" else "partial" end) as $hw_conf
| ($resolved | length) as $resolved_cp_n
| (if $delegate_topology == "integrated" and $rev_conf == "unavailable" and $resolved_cp_n > 0
   then "v2-integrated topology with \($resolved_cp_n) resolved checkpoint(s) but zero REVIEWER-TOKEN-EVENT captured — reviewer share is a real gap, not a clean zero"
   else null end) as $rev_gap_note
| ([ $rev_block_note, $rev_event_notes, $rev_gap_note ] | map(select(. != null)) | unique | if length > 0 then join("; ") else null end) as $rev_note

| (if $processed_total == 0
   then {value:null,confidence:"unavailable",_note:"processed_total is 0 — rework_ratio undefined"}
   elif ($rework_ids | length) == 0 then {value:0.0,confidence:$pt_conf}
   else {value:($rework_processed / $processed_total),confidence:$pt_conf} end) as $rework_ratio
| (if $posthoc == null
   then {value:null,confidence:"unavailable",_note:"no post-hoc aggregator fragment — tokens_per_loop unavailable"}
   elif $total_loops == 0
   then {value:null,confidence:"unavailable",_note:"total critic_loops is 0"}
   else {value:($processed_total / $total_loops),confidence:$pt_conf} end) as $tokens_per_loop
| (if $total_loops == 0
   then {value:null,confidence:"unavailable",_note:"total critic_loops is 0"}
   else {value:($active_time / 60 / $total_loops),confidence:$active_conf} end) as $minutes_per_loop
| (if $human_wait == 0
   then {value:null,confidence:"unavailable",_note:"human_wait_total_s is 0 — no resolved checkpoints"}
   else {value:($active_time / $human_wait),confidence:(if $active_conf == "exact" and $hw_conf == "exact" then "exact" else "partial" end)} end) as $avb
| (if $posthoc == null then [] else [($posthoc.specialists // [])[] | select(.confidence == "inferred" or .attempt_id == null)] end) as $unattributed
| (reduce ($pairs[] | select((.attempt_id | startswith("__malformed__")) | not)) as $sp ({};
    . + {($sp.attempt_id):{
      at:$sp.at, started_at:$sp.started_at,
      duration_s:({value:$sp.dur_value,confidence:$sp.dur_conf} + (if $sp.dur_note != null then {_note:$sp.dur_note} else {} end)),
      turns:null, tokens:null, rework:$sp.rework
    }}
  )) as $spawn_tokens_map
| {
    tokens:{
      processed_total:({value:$processed_total,confidence:$pt_conf}
        + (if ($pt_notes | length) > 0 then {_note:($pt_notes | join("; "))} else {} end)
        + {_semantics:"processed sums per-turn cumulative usage (input + cache_creation + cache_read) across deduped messages — a billing-shaped figure that scales with turn count, not a unique-token count; use for before/after comparisons only"}),
      output_total:({value:($spec_output + $cond_output + $del_output + $rev_output),confidence:(if $posthoc == null then "unavailable" else "estimated" end)}
        + (if $posthoc == null then {_note:"no post-hoc aggregator fragment — per-leg output source unavailable"} else {} end)),
      rework_ratio:$rework_ratio,
      tokens_per_loop:$tokens_per_loop,
      unattributed_records:$unattributed
    },
    conductor_tokens:{tokens:zero_tokens,turns:0,legs:0,confidence:"unavailable",_note:"per-leg tokens supplied by post-hoc aggregation at the account-run merge"},
    delegate_tokens:{tokens:zero_tokens,turns:0,legs:0,confidence:"unavailable",_note:"per-leg tokens supplied by post-hoc aggregation at the account-run merge"},
    reviewer_tokens:({tokens:{input:$rev_input,cache_creation:$rev_cc,cache_read:$rev_cr,processed:$rev_processed,output:$rev_output},turns:$rev_turns,spawns:($rev|length),confidence:$rev_conf}
      + (if $rev_note != null then {_note:$rev_note} else {} end)),
    wall_clock:{
      active_spawn_time_s:({value:$active_time,confidence:$active_conf,_semantics:"summed active time of individual spawns — not run wall-clock: parallel spawns sum to more than the wall-clock they overlapped in, and human-wait between spawns is excluded"}
        + (if $active_note != null then {_note:$active_note} else {} end)),
      minutes_per_loop:$minutes_per_loop
    },
    checkpoints:{
      entries:($cps | map({id,raised_at,resolved_at,wait_s:({value:.wait_value,confidence:.wait_conf} + (if .wait_note != null then {_note:.wait_note} else {} end)),decision})),
      human_wait_total_s:({value:$human_wait,confidence:$hw_conf} + (if $hw_conf == "partial" then {_note:"one or more checkpoints were raised but never resolved — excluded from human_wait_total_s"} else {} end)),
      active_vs_blocked_ratio:$avb
    },
    spawn_tokens:$spawn_tokens_map
  }
| . + (if ($parse_notes | length) > 0 then {_notes:$parse_notes} else {} end)
JQ
)

if jq -n \
  --slurpfile spawn_events "$se_f" \
  --slurpfile reviewers "$rv_f" \
  --slurpfile checkpoints "$cp_f" \
  --slurpfile parse_notes "$nt_f" \
  --argjson critic_loops "$critic_loops_json" \
  --arg delegate_topology "$delegate_topology" \
  --argjson posthoc "$posthoc_json" \
  "$JQ_PROG"; then
  exit 0
fi

echo "[account-tokens] jq failed to assemble metrics for $RUN_DIR" >&2
exit 1
