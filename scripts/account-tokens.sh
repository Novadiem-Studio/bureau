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
# SIX-VALUE CONFIDENCE ENUM (schema 2): exact | estimated | inferred |
# unavailable | partial | suspect. "partial" = the sum of the shares that are
# present, with the pending shares named in a sibling _note. "suspect" = the
# figure is complete but its inputs are actively distrusted — used by the
# timestamp-integrity guard on active_spawn_time_s when the narrative
# SPAWN-EVENT times are detected as fabricated (see the guard below and
# docs/run-accounting.md § B4).
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

# --- non-object `tokens` tolerance (schema-2 guard) ----------------------------
# The canonical schema-2 shape is tokens:{input,cache_creation,cache_read,
# processed,output} — an OBJECT. But some events get logged with `tokens` as a
# bare scalar number (e.g. "tokens":96666 — the Agent tool's
# <usage><subagent_tokens>N</subagent_tokens> summary). jq's `// 0` catches null
# but NOT a type error: `(number).processed` throws "Cannot index number with
# string" and crashes the whole parser, which cascades into account-run.sh's
# WARNING path and silently drops the run to schema_version 1. The `objects`
# filter passes a value through only when it IS an object (else empty → `// 0`
# supplies the default), so every `.tokens.<field>` read below is written as
# `(.tokens | objects | .<field>) // 0`: a scalar/absent `tokens` contributes 0
# to every field and never crashes. Count the non-object records here so we can
# surface an advisory note (they are skipped for numeric purposes, not fatal).
| ($spawn_tokens | map(select((.tokens | type) != "object")) | length) as $st_nonobj_n

# --- SPAWN-TOKEN-EVENT: dedup by agent_id, take-max processed (EC 11 / AC 16) --
| ($spawn_tokens | group_by(.agent_id) | map(max_by((.tokens | objects | .processed) // 0))) as $stok
| ($stok | map(.attempt_id) | map(select(. != null))) as $stok_ids
| ($started | map(.attempt_id)) as $started_ids

# specialist share (sum over the deduped set — each agent_id counted once)
| ($stok | map((.tokens | objects | .processed) // 0) | add // 0) as $spec_processed
| ($stok | map((.tokens | objects | .output) // 0)    | add // 0) as $spec_output

# every terminal SPAWN-EVENT must have a matched SPAWN-TOKEN-EVENT (FR 10 (b))
| ($terminals | map(.attempt_id) | map(select(. as $tid | ($stok_ids | index($tid)) == null))) as $unmatched_terminals
| ($unmatched_terminals | length) as $n_unmatched

# --- CONDUCTOR-TOKEN-EVENT: dedup per session_id take-max, sum across legs -----
# Same non-object `tokens` tolerance as the specialist block above: a scalar
# `tokens` on a conductor leg contributes 0 to each field instead of crashing.
| ($conductor | map(select((.tokens | type) != "object")) | length) as $cond_nonobj_n
| ($conductor | group_by(.session_id) | map(max_by((.tokens | objects | .processed) // 0))) as $cond
| ($conductor | group_by(.session_id) | map(map(.final == true) | any)) as $leg_finals
| (($conductor | length) > 0 and ($leg_finals | all)) as $all_legs_final
| ($cond | length) as $legs
| ($cond | map((.tokens | objects | .input) // 0)          | add // 0) as $cond_input
| ($cond | map((.tokens | objects | .cache_creation) // 0) | add // 0) as $cond_cc
| ($cond | map((.tokens | objects | .cache_read) // 0)     | add // 0) as $cond_cr
| ($cond | map((.tokens | objects | .processed) // 0)      | add // 0) as $cond_processed
| ($cond | map((.tokens | objects | .output) // 0)         | add // 0) as $cond_output
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

# --- timestamp-integrity guard: refuse to bless FABRICATED narrative times ----
# active_spawn_time_s is summed from the *narrative* SPAWN-EVENT `at` fields, which
# the Conductor (an LLM) writes and can fabricate when it does not shell out to
# `date`. On run 20260709-liquid-glass-nav the narrative terminals were tidy round
# hours 00:00→07:00 on the WRONG calendar date, so active_time = 43200s wore an
# "exact" badge — a fabricated 12h. The unfakeable tell sat in the same log: the
# hook-emitted SPAWN-TOKEN-EVENT `at` (subagent-stop.sh runs `date -u`) read the
# real clock. Two tells force active_spawn_time_s off "exact":
#
#  (1) HOOK CROSS-CHECK (primary, strongest). For each attempt that has BOTH a
#      narrative terminal `at` AND a same-attempt_id hook SPAWN-TOKEN-EVENT `at`,
#      both mark ~spawn completion, so they should agree closely. TOLERANCE = 900s
#      (15 min): generous headroom for the legitimate gap between when the
#      SubagentStop hook fires (`date -u`) and when the Conductor separately logs
#      its terminal SPAWN-EVENT line, while far tighter than the 12h / wrong-date
#      fabrication. Different calendar date OR |Δ| > 900s ⇒ that attempt's narrative
#      time is fabricated. Even ONE tainted attempt taints the whole active_time sum.
#  (2) ALL-ROUND-HOUR (secondary — a genuine FALLBACK, only when no hook has
#      vouched for the times). If there are >=2 narrative spawn timestamps (started +
#      terminal `at`) and they ALL land exactly on :00:00 (epoch % 3600 == 0), that
#      is fabrication — a real process does not repeatedly complete on the exact
#      hour. But this heuristic must yield to hard evidence: if ANY attempt has an
#      agreeing hook `at` (same date, within tolerance), an independent unfakeable
#      clock has vouched that those times are REAL, so round-ness alone must NOT
#      override it. So (2) only implies fabrication when NO agreeing hook exists
#      (`$all_round_hour and ($any_hook_agrees | not)`). A single coincidental
#      :00:00 must NOT trip it either (require ALL and >=2). By contrast a
#      DISAGREEING hook (1) is always a positive fabrication signal — never gated.
#
# The hook `at` per attempt_id (deduped SPAWN-TOKEN-EVENT set $stok, take-max), and
# the narrative terminal `at` per attempt ($pairs). A per-attempt cross-check row:
| ([ $pairs[]
     | . as $p
     | ($stok | map(select(.attempt_id == $p.attempt_id)) | .[0]) as $tok
     | select($p.attempt_id != null and $tok != null)
     | ($p.at | tsnum) as $narr
     | ($tok.at | tsnum) as $hook
     | select($narr != null and $hook != null)
     | { attempt_id: $p.attempt_id,
         narr: $p.at, hook: $tok.at,
         delta_s: (($narr - $hook) | if . < 0 then -. else . end),
         # UTC calendar date (YYYY-MM-DD) of each; a mismatch is itself a tell.
         diff_date: (($narr | . - (. % 86400)) != ($hook | . - (. % 86400))) } ]) as $xcheck
| ($xcheck | map(select(.diff_date or (.delta_s > 900)))) as $xcheck_bad
| (($xcheck_bad | length) > 0) as $hook_disagree
# At least one attempt whose narrative and hook `at` AGREE (same UTC date AND
# |Δ| <= 900s) — an independent unfakeable clock vouching the times are real.
| (($xcheck | map(select((.diff_date | not) and (.delta_s <= 900))) | length) > 0) as $any_hook_agrees

# (2) all-round-hour tell over the narrative spawn timestamps (started + terminal).
| ([ $pairs[] | (.started_at | tsnum), (.at | tsnum) ] | map(select(. != null))) as $narr_ts
| (($narr_ts | length) >= 2 and ($narr_ts | map(. % 3600 == 0) | all)) as $all_round_hour

# A disagreeing hook is always fabrication; the round-hour heuristic is a fallback
# that yields to any agreeing-hook evidence (W1 — round-ness must not override a
# hook that has vouched the times are real).
| ($hook_disagree or ($all_round_hour and ($any_hook_agrees | not))) as $ts_fabricated
| (if $hook_disagree
   then ($xcheck_bad | .[0]) as $b
     | "active_spawn_time_s: narrative SPAWN-EVENT time disagrees with hook SPAWN-TOKEN-EVENT time for attempt \($b.attempt_id) (narrative \($b.narr) vs hook \($b.hook)"
       + (if $b.diff_date then ", different calendar date" else ", Δ\((($b.delta_s)/60|floor))m > 15m tolerance" end)
       + ") — narrative times treated as fabricated, not exact"
   elif ($all_round_hour and ($any_hook_agrees | not))
   then "active_spawn_time_s: all \($narr_ts | length) narrative SPAWN-EVENT timestamps land exactly on the round hour (:00:00) with no agreeing hook to vouch for them — treated as fabricated (LLM-typed), not exact"
   else null end) as $ts_note

# active_conf: "exact" only when every duration parsed AND no fabrication tell fired.
# A fired tell forces "suspect" (a distrusted-but-present figure — NOT "partial",
# which means incomplete data; see docs/run-accounting.md § B4). No consumer switches
# on this field's confidence string (account-run.sh reads only `.value`; grep-verified),
# so the new enum value is consumer-safe.
| (if ($active_all_exact | not) then "partial"
   elif $ts_fabricated then "suspect"
   else "exact" end) as $active_conf

# --- rework numerator: processed over spawns flagged rework:true (FR 9) -------
| ($pairs | map(select(.rework == true) | .attempt_id)) as $rework_ids
| ([ $rework_ids[] as $rid
     | ($stok | map(select(.attempt_id == $rid)) | map((.tokens | objects | .processed) // 0) | max // 0)
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
        ($stok | map(select(.attempt_id == $sp.attempt_id)) | max_by((.tokens | objects | .processed) // 0)) as $tok
        | {
            at: $sp.at,
            started_at: $sp.started_at,
            duration_s: ({value: $sp.dur_value, confidence: $sp.dur_conf}
                         + (if $sp.dur_note != null then {_note: $sp.dur_note} else {} end)),
            turns: (if $tok != null then ($tok.turns // 0) else null end),
            # Emit tokens only when it is a genuine object — a spawn whose only
            # record carried a scalar `tokens` yields null here (treated like an
            # unmatched spawn), so account-run.sh's `$stk.tokens | with_entries`
            # enrichment never receives a scalar and crashes downstream.
            tokens: (if ($tok != null and (($tok.tokens | type) == "object")) then $tok.tokens else null end),
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
      active_spawn_time_s: ({value: $active_time, confidence: $active_conf,
        _semantics: "summed active time of individual spawns — not run wall-clock: parallel spawns sum to more than the wall-clock they overlapped in, and human-wait between spawns is excluded"}
        + (if $ts_note != null then {_note: $ts_note} else {} end)),
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
  # Merge torn-line parse notes with a non-object-`tokens` advisory (both land in
  # _notes). ($st_nonobj_n + $cond_nonobj_n) counts every SPAWN-TOKEN-EVENT /
  # CONDUCTOR-TOKEN-EVENT whose `tokens` was a non-object (scalar) and so
  # contributed 0 instead of crashing — surfaced, not silently swallowed.
  | ($st_nonobj_n + $cond_nonobj_n) as $nonobj_total
  | . + (if (($parse_notes | length) > 0) or ($nonobj_total > 0)
         then {_notes: ($parse_notes
                        + (if $nonobj_total > 0
                           then ["\($nonobj_total) token event(s) had a non-object (scalar) `tokens` field — counted as 0, not fatal"]
                           else [] end))}
         else {} end)
  # Advisory stderr line (nice-to-have): mirrors account-run.sh's WARNING lane.
  # `debug` writes ["DEBUG:", …] to STDERR and passes its input through unchanged
  # on stdout, so the single-value JSON fragment account-run.sh captures is
  # untouched. Gated on $nonobj_total so a clean run emits nothing.
  | if $nonobj_total > 0
    then debug("[account-tokens] NOTE: skipped \($nonobj_total) malformed (non-object) token event(s)")
    else . end
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
