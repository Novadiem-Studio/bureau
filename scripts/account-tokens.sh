#!/usr/bin/env bash
# account-tokens.sh <RUN_DIR> — Bundle 11 derived-metrics consumer.
#
# Reads RUN_DIR/log.md and RUN_DIR/state.json ONLY. It NEVER reads a session
# transcript (the SubagentStop/Stop hooks are the only transcript readers).
# Emits one self-contained JSON fragment on STDOUT and writes nothing into
# RUN_DIR (FR 8 channel pin — stdout is the only output channel; there is no
# intermediate file that could race or leak). account-run.sh (Phase 5)
# captures this stdout and merges it inside its own § 9 tmp pipeline.
#
# Reads four log.md line types (dedup + confidence rules per FR 8/9/10):
#   SPAWN-EVENT:           started/terminal spawn records (pair by attempt_id)
#   SPAWN-TOKEN-EVENT:     per-subagent token totals (dedup by agent_id take-max)
#   CONDUCTOR-TOKEN-EVENT: per-session conductor totals (dedup by session_id
#                          take-max, then sum across distinct sessions)
#   CHECKPOINT-EVENT:      raised/resolved pairs (wait_s consumer-derived)
#
# The consumer is a lock-free reader of log.md: a half-written or malformed
# event line is skipped + recorded in _notes (EC 13 / torn-line tolerance),
# never a crash. It mirrors account-run.sh's Step 6.2 per-line parse gate.
#
# FIVE-VALUE CONFIDENCE ENUM (schema 2): exact | estimated | inferred |
# unavailable | partial. "partial" = the sum of the shares that are present,
# with the pending shares named in a sibling _note.
#
# Portability: Bash 3.2 + jq on macOS. No associative arrays, no GNU-only date
# flags, no file-locking CLI. All time arithmetic happens in jq via
# fromdateiso8601.

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "[account-tokens] usage: account-tokens.sh <RUN_DIR>" >&2
  exit 2
fi

LOG_MD="$RUN_DIR/log.md"
STATE_JSON="$RUN_DIR/state.json"

# ── Scratch workspace (JSONL staging files; removed on exit) ──────────────────
tmpd=$(mktemp -d "${TMPDIR:-/tmp}/account-tokens.XXXXXX") || {
  echo "[account-tokens] mktemp failed" >&2
  exit 1
}
trap 'rm -rf "$tmpd"' EXIT

se_f="$tmpd/spawn_events.jsonl";  : > "$se_f"   # SPAWN-EVENT payloads
st_f="$tmpd/spawn_tokens.jsonl";  : > "$st_f"   # SPAWN-TOKEN-EVENT payloads
ct_f="$tmpd/conductor.jsonl";     : > "$ct_f"   # CONDUCTOR-TOKEN-EVENT payloads
cp_f="$tmpd/checkpoints.jsonl";   : > "$cp_f"   # CHECKPOINT-EVENT payloads
nt_f="$tmpd/notes.jsonl";         : > "$nt_f"   # skipped-line _notes (JSONL of strings)

# ── Part A: parse log.md line by line, classify by prefix, gate each payload ──
# `|| [ -n "$line" ]` catches a final line with no trailing newline — the exact
# shape of a torn/truncated last event line (EC 13).
lineno=0
if [ -r "$LOG_MD" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # SPAWN-TOKEN-EVENT MUST be tested before SPAWN-EVENT (shared "SPAWN-" stem).
    case "$line" in
      "SPAWN-TOKEN-EVENT: "*)
        prefix="SPAWN-TOKEN-EVENT"; dest="$st_f"; payload="${line#SPAWN-TOKEN-EVENT: }" ;;
      "SPAWN-EVENT: "*)
        prefix="SPAWN-EVENT"; dest="$se_f"; payload="${line#SPAWN-EVENT: }" ;;
      "CONDUCTOR-TOKEN-EVENT: "*)
        prefix="CONDUCTOR-TOKEN-EVENT"; dest="$ct_f"; payload="${line#CONDUCTOR-TOKEN-EVENT: }" ;;
      "CHECKPOINT-EVENT: "*)
        prefix="CHECKPOINT-EVENT"; dest="$cp_f"; payload="${line#CHECKPOINT-EVENT: }" ;;
      *)
        continue ;;   # not a Bundle 11 event line — skip silently
    esac
    # Parse gate: payload must be exactly one valid JSON object. `-s` slurps the
    # payload; length==1 rejects a torn line that resolves to two values, and the
    # object type check rejects a bare scalar. Any parse error → non-zero exit.
    if printf '%s' "$payload" | jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
      printf '%s\n' "$payload" >> "$dest"
    else
      jq -cn --arg n "line ${lineno}: unparseable ${prefix} payload — skipped (torn or malformed JSON)" '$n' >> "$nt_f"
    fi
  done < "$LOG_MD"
fi

# ── Part C: critic_loops from state.json (null-safe; total loops = sum values) ─
critic_loops_json="null"
if [ -r "$STATE_JSON" ]; then
  cl=$(jq -c 'if (has("critic_loops") and ((.critic_loops | type) == "object")) then .critic_loops else null end' "$STATE_JSON" 2>/dev/null) || cl="null"
  [ -n "$cl" ] && critic_loops_json="$cl"
fi

# ── Part C (continued): resumed_legs from state.json (absent/non-number → 0) ───
resumed_legs=0
if [ -r "$STATE_JSON" ]; then
  _rl=$(jq -r 'if (has("resumed_legs") and ((.resumed_legs|type)=="number")) then .resumed_legs else 0 end' "$STATE_JSON" 2>/dev/null) || _rl=0
  [ -n "$_rl" ] && resumed_legs="$_rl"
fi

# ── Part D: derive every metric in a single jq pass and emit on stdout ────────
JQ_PROG=$(cat <<'JQ'
# Bare-string-safe ISO-8601 parse: a valid FR-1 %Y-%m-%dT%H:%M:%SZ string →
# epoch seconds; anything malformed/absent → null (never a crash). This is the
# in-jq equivalent of the pinned `printf '%s' "$val" | jq -Re 'fromdateiso8601'`
# validation — same accept/reject set, applied per timestamp before arithmetic
# (EC 13). Because the value is already a parsed JSON string here, the -R raw
# pitfall (bare unquoted string failing JSON import) cannot occur.
def tsnum: if type == "string" then (try fromdateiso8601 catch null) else null end;

# --- Specialist spawns: started (deduped by attempt_id, first) + terminals ----
($spawn_events | map(select(.status == "started")) | group_by(.attempt_id) | map(.[0])) as $started
| ($spawn_events | map(select(
      .status == "complete" or .status == "no-handoff"
      or .status == "failed" or .status == "terminated"))) as $terminals

# --- SPAWN-TOKEN-EVENT: dedup by agent_id, take-max processed (EC 11 / AC 16) --
| ($spawn_tokens | group_by(.agent_id) | map(max_by(.tokens.processed // 0))) as $stok
| ($stok | map(.attempt_id) | map(select(. != null))) as $stok_ids
| ($started | map(.attempt_id)) as $started_ids

# specialist share (sum over the deduped set — each agent_id counted once)
| ($stok | map(.tokens.processed // 0) | add // 0) as $spec_processed
| ($stok | map(.tokens.output // 0)    | add // 0) as $spec_output

# every terminal SPAWN-EVENT must have a matched SPAWN-TOKEN-EVENT (FR 10 (b))
| ($terminals | map(.attempt_id) | map(select(. as $tid | ($stok_ids | index($tid)) == null))) as $unmatched_terminals
| ($unmatched_terminals | length) as $n_unmatched

# --- CONDUCTOR-TOKEN-EVENT: dedup per session_id take-max, sum across legs -----
| ($conductor | group_by(.session_id) | map(max_by(.tokens.processed // 0))) as $cond
| ($conductor | group_by(.session_id) | map(map(.final == true) | any)) as $leg_finals
| (($conductor | length) > 0 and ($leg_finals | all)) as $all_legs_final
| ($cond | length) as $legs
| ($cond | map(.tokens.input // 0)          | add // 0) as $cond_input
| ($cond | map(.tokens.cache_creation // 0) | add // 0) as $cond_cc
| ($cond | map(.tokens.cache_read // 0)     | add // 0) as $cond_cr
| ($cond | map(.tokens.processed // 0)      | add // 0) as $cond_processed
| ($cond | map(.tokens.output // 0)         | add // 0) as $cond_output
| ($cond | map(.turns // 0)                 | add // 0) as $cond_turns

# --- processed_total + confidence lattice (FR 9 / FR 10) ----------------------
| ($spec_processed + $cond_processed) as $processed_total
| ($all_legs_final) as $cond_ok
| ($n_unmatched == 0) as $spec_ok
| (if $cond_ok and $spec_ok then "exact" else "partial" end) as $pt_conf
| ([ (if ($cond_ok | not) then "conductor-share-pending: final-leg capture not yet in log.md" else empty end),
     (if ($spec_ok | not) then "\($n_unmatched) specialist spawn(s) have no matched SPAWN-TOKEN-EVENT" else empty end)
   ]) as $pt_notes

# conductor_tokens block confidence
| (if $all_legs_final then "exact"
   elif ($conductor | length) > 0 then "partial"
   else "unavailable" end) as $cond_conf
| (if $cond_conf == "partial" then "final-leg-capture-pending: post-close-out Stop hook has not yet fired for this run"
   elif $cond_conf == "unavailable" then "no CONDUCTOR-TOKEN-EVENT lines present in log.md yet"
   else null end) as $cond_block_note

# --- FR 5: suspicious-multi-leg note (more legs than recorded resumes explain) -
| ($legs > ($resumed_legs + 1)) as $suspicious_multi_leg
| (if $suspicious_multi_leg
   then "\($legs) conductor legs detected with no resume evidence in state.json — verify all are legitimate conductor legs; a foreign session may have been captured."
   else null end) as $suspicious_note

# --- FR 5: merge cond-block note + suspicious note (both can co-fire) ----------
| ([
    (if $cond_block_note != null then $cond_block_note else empty end),
    (if $suspicious_note != null then $suspicious_note else empty end)
  ] | if length > 0 then join("; ") else null end) as $combined_note

# --- per-spawn duration_s (consumer-derived, <=0 guard, both-parse rule) ------
| ($started | map(
    . as $s
    | ($terminals | map(select(.attempt_id == $s.attempt_id)) | .[0]) as $t
    | ($s.at | tsnum) as $sn
    | (($t.at) | tsnum) as $tn
    | (if $t == null then null
       elif ($sn == null or $tn == null) then null
       else ($tn - $sn) end) as $dur
    | {
        attempt_id: $s.attempt_id,
        rework: ($s.rework // false),
        started_at: $s.at,
        at: (if $t != null then $t.at else $s.at end),
        dur_value: $dur,
        dur_conf: (if ($t != null and $sn != null and $tn != null) then "exact" else "unavailable" end),
        dur_note: (if ($dur != null and $dur <= 0) then "duration_s <= 0 — emitted as-is (clock skew or identical timestamps), not corrected or discarded" else null end)
      }
  )) as $pairs

| ($pairs | map(select(.dur_conf == "exact")) | map(.dur_value) | add // 0) as $active_time
| ($pairs | map(.dur_conf == "exact") | all) as $active_all_exact
| (if $active_all_exact then "exact" else "partial" end) as $active_conf

# --- rework numerator: processed over spawns flagged rework:true (FR 9) -------
| ($pairs | map(select(.rework == true) | .attempt_id)) as $rework_ids
| ([ $rework_ids[] as $rid
     | ($stok | map(select(.attempt_id == $rid)) | map(.tokens.processed // 0) | max // 0)
   ] | add // 0) as $rework_processed

# --- total critic loops (sum of critic_loops values; null-safe) ---------------
| (if ($critic_loops | type) == "object"
   then ([$critic_loops[]] | map(select(type == "number")) | add // 0)
   else 0 end) as $total_loops

# --- checkpoints: pair raised/resolved by id, derive wait_s -------------------
| ($checkpoints | map(select(.status == "raised"))   | group_by(.id) | map(.[0])) as $raised
| ($checkpoints | map(select(.status == "resolved"))) as $resolved
| ($raised | map(
    . as $r
    | ($resolved | map(select(.id == $r.id)) | .[0]) as $res
    | ($r.at | tsnum) as $rn
    | (($res.at) | tsnum) as $vn
    | (if $res == null then null
       elif ($rn == null or $vn == null) then null
       else ($vn - $rn) end) as $w
    | {
        id: $r.id,
        raised_at: $r.at,
        resolved_at: (if $res != null then $res.at else null end),
        decision: (if $res != null then ($res.decision // null) else null end),
        wait_value: $w,
        wait_conf: (if ($res != null and $rn != null and $vn != null) then "exact" else "unavailable" end),
        wait_note: (if ($w != null and $w <= 0) then "wait_s <= 0 — emitted as-is, not corrected or discarded" else null end)
      }
  )) as $cps
| ($cps | map(select(.wait_conf == "exact")) | map(.wait_value) | add // 0) as $human_wait
| ($cps | map(.wait_conf == "exact") | all) as $cp_all_resolved
| (if $cp_all_resolved then "exact" else "partial" end) as $hw_conf

# --- derived: null-safe division blocks ---------------------------------------
| (if $processed_total == 0 then {value: null, confidence: "unavailable", _note: "processed_total is 0 — rework_ratio undefined"}
   elif ($rework_ids | length) == 0 then {value: 0.0, confidence: $pt_conf}
   else {value: ($rework_processed / $processed_total), confidence: $pt_conf} end) as $rework_ratio
| (if $total_loops == 0 then {value: null, confidence: "unavailable", _note: "total critic_loops is 0"}
   else {value: ($processed_total / $total_loops), confidence: $pt_conf} end) as $tokens_per_loop
| (if $total_loops == 0 then {value: null, confidence: "unavailable", _note: "total critic_loops is 0"}
   else {value: ($active_time / 60 / $total_loops), confidence: $active_conf} end) as $minutes_per_loop
| (if ($human_wait == 0) then {value: null, confidence: "unavailable", _note: "human_wait_total_s is 0 — no resolved checkpoints"}
   else {value: ($active_time / $human_wait),
         confidence: (if ($active_conf == "exact" and $hw_conf == "exact") then "exact" else "partial" end)} end) as $avb

# --- unattributed SPAWN-TOKEN-EVENTs (surfaced, still counted) ----------------
| ($stok | map(. as $r | select(($r.attempt_id == null) or (($started_ids | index($r.attempt_id)) == null)))) as $unattributed

# --- spawn_tokens map keyed by attempt_id (for account-run.sh Step 6.6) -------
| (reduce $pairs[] as $sp ({};
    . + {
      ($sp.attempt_id): (
        ($stok | map(select(.attempt_id == $sp.attempt_id)) | max_by(.tokens.processed // 0)) as $tok
        | {
            at: $sp.at,
            started_at: $sp.started_at,
            duration_s: ({value: $sp.dur_value, confidence: $sp.dur_conf}
                         + (if $sp.dur_note != null then {_note: $sp.dur_note} else {} end)),
            turns: (if $tok != null then ($tok.turns // 0) else null end),
            tokens: (if $tok != null then $tok.tokens else null end),
            rework: $sp.rework
          }
      )
    }
  )) as $spawn_tokens_map

# --- final assembly -----------------------------------------------------------
| {
    tokens: {
      processed_total: ({value: $processed_total, confidence: $pt_conf}
                        + (if ($pt_notes | length) > 0 then {_note: ($pt_notes | join("; "))} else {} end)
                        + {_semantics: "processed sums per-turn cumulative usage (input + cache_creation + cache_read) across deduped messages — a billing-shaped figure that scales with turn count, not a unique-token count; use for before/after comparisons only"}),
      output_total: {value: ($spec_output + $cond_output), confidence: "estimated"},
      rework_ratio: $rework_ratio,
      tokens_per_loop: $tokens_per_loop,
      unattributed_records: $unattributed
    },
    conductor_tokens: ({
      tokens: {input: $cond_input, cache_creation: $cond_cc, cache_read: $cond_cr, processed: $cond_processed, output: $cond_output},
      turns: $cond_turns,
      legs: $legs,
      confidence: $cond_conf
    } + (if $combined_note != null then {_note: $combined_note} else {} end)),
    wall_clock: {
      active_spawn_time_s: {value: $active_time, confidence: $active_conf,
        _semantics: "summed active time of individual spawns — not run wall-clock: parallel spawns sum to more than the wall-clock they overlapped in, and human-wait between spawns is excluded"},
      minutes_per_loop: $minutes_per_loop
    },
    checkpoints: {
      entries: ($cps | map({
        id: .id,
        raised_at: .raised_at,
        resolved_at: .resolved_at,
        wait_s: ({value: .wait_value, confidence: .wait_conf}
                 + (if .wait_note != null then {_note: .wait_note} else {} end)),
        decision: .decision
      })),
      human_wait_total_s: ({value: $human_wait, confidence: $hw_conf}
                           + (if $hw_conf == "partial" then {_note: "one or more checkpoints were raised but never resolved — excluded from human_wait_total_s"} else {} end)),
      active_vs_blocked_ratio: $avb
    },
    spawn_tokens: $spawn_tokens_map
  }
  + (if ($parse_notes | length) > 0 then {_notes: $parse_notes} else {} end)
JQ
)

if jq -n \
  --slurpfile spawn_events "$se_f" \
  --slurpfile spawn_tokens "$st_f" \
  --slurpfile conductor "$ct_f" \
  --slurpfile checkpoints "$cp_f" \
  --slurpfile parse_notes "$nt_f" \
  --argjson critic_loops "$critic_loops_json" \
  --argjson resumed_legs "$resumed_legs" \
  "$JQ_PROG"; then
  exit 0
else
  echo "[account-tokens] jq failed to assemble metrics for $RUN_DIR" >&2
  exit 1
fi
