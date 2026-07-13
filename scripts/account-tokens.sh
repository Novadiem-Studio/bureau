#!/usr/bin/env bash
# account-tokens.sh <RUN_DIR> — Bundle 11 derived-metrics consumer.
#
# Reads RUN_DIR/log.md, RUN_DIR/state.json, and (guarded, backstop only)
# RUN_DIR/delegate-state.json — all sibling run-dir files. It NEVER reads a
# session transcript (the SubagentStop/Stop hooks are the only transcript
# readers); the FR-8 channel pin forbids transcripts, not this run-dir state file.
# Emits one self-contained JSON fragment on STDOUT and writes nothing into
# RUN_DIR (FR 8 channel pin — stdout is the only output channel; there is no
# intermediate file that could race or leak). account-run.sh (Phase 5)
# captures this stdout and merges it inside its own § 9 tmp pipeline.
#
# Reads six log.md line types (dedup + confidence rules per FR 8/9/10):
#   SPAWN-EVENT:           started/terminal spawn records (pair by attempt_id)
#   SPAWN-TOKEN-EVENT:     per-subagent token totals (dedup by agent_id take-max)
#   CONDUCTOR-TOKEN-EVENT: per-session conductor totals (dedup by session_id
#                          take-max, then sum across distinct sessions)
#   DELEGATE-TOKEN-EVENT:  per-session Delegate-manager totals (#26a — mirror of
#                          conductor: dedup by session_id take-max, sum across legs)
#   REVIEWER-TOKEN-EVENT:  per-spawn cold-reviewer totals (#26b — dedup by spawn_id
#                          take-max, then SUM across all spawn_ids; no baseline)
#   CHECKPOINT-EVENT:      raised/resolved pairs (wait_s consumer-derived)
# The three token-event prefixes are DISJOINT — a line has exactly one prefix, so
# the three role buckets never double-count (the anti-double-count invariant).
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
de_f="$tmpd/delegate.jsonl";      : > "$de_f"   # DELEGATE-TOKEN-EVENT payloads (#26a)
rv_f="$tmpd/reviewers.jsonl";     : > "$rv_f"   # REVIEWER-TOKEN-EVENT payloads (#26b)
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
      # DELEGATE- / REVIEWER- are disjoint exact prefixes (no shared stem with
      # CONDUCTOR- or with each other). Each line has exactly one prefix, so the
      # three roles are physically partitioned at parse time — THIS is the
      # anti-double-count invariant (#26): a delegate line can never land in the
      # conductor bucket, a reviewer line never in either. No cross-checking math.
      "DELEGATE-TOKEN-EVENT: "*)
        prefix="DELEGATE-TOKEN-EVENT"; dest="$de_f"; payload="${line#DELEGATE-TOKEN-EVENT: }" ;;
      "REVIEWER-TOKEN-EVENT: "*)
        prefix="REVIEWER-TOKEN-EVENT"; dest="$rv_f"; payload="${line#REVIEWER-TOKEN-EVENT: }" ;;
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

# ── Part C (continued): v2 topology from delegate-state.json (backstop guard) ──
# ONE guarded read of a sibling run-dir file (NOT a transcript — the FR-8 channel
# pin forbids transcripts, not this run-dir state file). Null-safe: absent /
# unreadable / unparseable / non-"integrated" ⇒ empty ⇒ the guard is inert. Only
# the literal value "integrated" arms the v2-capture-gap note below. Backstop:
# once the subagent-Conductor capture works this stays silent (its second
# condition requires confidence=="unavailable"); it fires only on a genuine gap.
delegate_topology=""
DELEGATE_STATE_JSON="$RUN_DIR/delegate-state.json"
if [ -r "$DELEGATE_STATE_JSON" ]; then
  _dt=$(jq -r 'if (type=="object") and (has("topology")) and ((.topology|type)=="string") then .topology else "" end' "$DELEGATE_STATE_JSON" 2>/dev/null) || _dt=""
  [ -n "$_dt" ] && delegate_topology="$_dt"
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

# ── Ingest normalization (F2 + F3): validate ONCE, here, so every downstream
# computation — spawn/specialist, conductor, delegate, reviewer, dedup, totals,
# and the spawn_tokens map account-run.sh enriches — sees clean data. Enforcing
# the invariants at the ingest boundary (not at every use) closes F2 (a malformed
# field isolates instead of aborting the whole pass to schema-1) and F3 (processed
# is derived for ALL buckets at once, no per-bucket guard to remember). ──────────
def coerce_tokens:
  # Accept only an OBJECT tokens; a scalar/absent tokens becomes the zero object.
  # Coerce each numeric field with `numbers // 0` (a string/object/null field → 0;
  # a legit 0 survives — `//` only substitutes on null/false/empty, and `0 | numbers`
  # is 0), then DERIVE processed authoritatively from the coerced components. A
  # stored `.processed` is an ASSERTION, never authority: record disagreement so
  # the F3 identity note can fire.
  (if type == "object" then . else {} end) as $t
  | ($t.input          | numbers // 0) as $in
  | ($t.cache_creation | numbers // 0) as $cc
  | ($t.cache_read     | numbers // 0) as $cr
  | ($t.output         | numbers // 0) as $out
  | ($t.processed) as $stated
  | ($in + $cc + $cr) as $derived
  | { input: $in, cache_creation: $cc, cache_read: $cr,
      processed: $derived, output: $out,
      _stated_processed: $stated };

def normalize_event($required):
  . as $e
  | (.tokens | coerce_tokens) as $tk
  # turns: coerce to a number (a string/object/null → 0).
  | (.turns | numbers // 0) as $turns
  # $ord = the stable pre-group array index of THIS record within its stream,
  # threaded in by the rebind (`._ord` set by `to_entries|map(.value+{_ord:.key})`).
  # It is what makes each synthetic isolate key UNIQUE per record, so two malformed
  # records in the same stream stay TWO distinct group keys (F1 no-collapse), never
  # a single shared sink that would re-collapse them. `_ord` is deleted from the
  # emitted record so it never leaks into downstream reads or the output.
  | (.["_ord"] // 0) as $ord
  # ISOLATE, don't coerce-to-null. Every value later used as a jq object KEY or a
  # group_by key must be a LEGAL, UNIQUE key on a malformed record. A non-string
  # (or absent) attempt_id/agent_id/session_id/spawn_id is isolated to a DISTINCT
  # synthetic string key `__malformed__<field>__<ord>`:
  #   - a legal object key (fixes F3: "Cannot use null/object as object key"), and
  #   - unique per record (fixes F1: two malformed records no longer group_by(null)
  #     into ONE bucket — each keeps its own synthetic key).
  # A valid string id is kept VERBATIM (byte-identity on valid input — the gate).
  # A PRESENT-but-wrong-typed id (object/number/bool) isolates to a synthetic key.
  # An ABSENT/null id stays null: it never was a key on this record (a SPAWN-TOKEN-
  # EVENT has no session_id/spawn_id; a CONDUCTOR has no spawn_id). Keeping null→null
  # is what preserves byte-identity — every stream's records get exactly the same
  # null id-fields they got before, only a PRESENT malformed value now becomes a
  # synthetic string instead of null. The F1 vector (an object spawn_id on a reviewer)
  # is a present-but-wrong-typed value, so it is caught here. Uniform across all four
  # keys: wrong-type → synthetic, null → null.
  # FR 5 (required fields): for a field in $required, an absent/null OR empty-string
  # value also isolates to a synthetic key (EC 4 — mirrors account-run.sh's three-mode
  # rule for SPAWN-EVENT). SPAWN-EVENT has $required == [] so its null branches are
  # byte-identical to the old code. Token streams get per-stream required arrays.
  | (if (.attempt_id | type) == "string" and (.attempt_id != "")
         then .attempt_id
       elif (($required | index("attempt_id")) != null)
            and ((.attempt_id // "") == "")
         then "__malformed__attempt_id__\($ord)"
       elif (.attempt_id == null) then null
       elif (.attempt_id == "") then ""
       else "__malformed__attempt_id__\($ord)" end) as $aid
  | (if (.agent_id | type) == "string" and (.agent_id != "")
         then .agent_id
       elif (($required | index("agent_id")) != null)
            and ((.agent_id // "") == "")
         then "__malformed__agent_id__\($ord)"
       elif (.agent_id == null) then null
       elif (.agent_id == "") then ""
       else "__malformed__agent_id__\($ord)" end) as $gid
  | (if (.session_id | type) == "string" and (.session_id != "")
         then .session_id
       elif (($required | index("session_id")) != null)
            and ((.session_id // "") == "")
         then "__malformed__session_id__\($ord)"
       elif (.session_id == null) then null
       elif (.session_id == "") then ""
       else "__malformed__session_id__\($ord)" end) as $sid
  | (if (.spawn_id | type) == "string" and (.spawn_id != "")
         then .spawn_id
       elif (($required | index("spawn_id")) != null)
            and ((.spawn_id // "") == "")
         then "__malformed__spawn_id__\($ord)"
       elif (.spawn_id == null) then null
       elif (.spawn_id == "") then ""
       else "__malformed__spawn_id__\($ord)" end) as $pid
  # $isolated is true when this record's key field was isolated to a synthetic key
  # (wrong-typed for attempt/agent; wrong-typed OR absent for session/spawn). It is
  # tagged onto the record and AND'd (via the per-stream $*_isolated flags) into every
  # confidence gate so a bucket that absorbed an isolated record is never `exact`.
  | ((($aid | type) == "string" and ($aid | startswith("__malformed__")))
     or (($gid | type) == "string" and ($gid | startswith("__malformed__")))
     or (($sid | type) == "string" and ($sid | startswith("__malformed__")))
     or (($pid | type) == "string" and ($pid | startswith("__malformed__")))) as $isolated
  # FR 6 / A4: when $required is non-empty (token streams only; SPAWN-EVENT has
  # $required == []) AND raw .tokens is absent or null → isolate the record. This rides
  # the existing $*_isolated → block-gate confidence path (AS 5). SPAWN-EVENT
  # ($required == []) is structurally excluded (EC 6).
  | (($required | length) > 0 and (($e.tokens // null) == null)) as $tokens_absent
  | (if $tokens_absent then true else $isolated end) as $isolated
  # Malformed / disagreement breadcrumbs, collected per-event so the pass can
  # surface them. The "stated processed != derived" breadcrumb is the F3 signal:
  # a stored processed (numeric or not) that disagrees with the derived component
  # sum. The F3 identity note below re-sources itself from this breadcrumb.
  | ([ (if ($e.tokens | type) != "object" and ($e.tokens != null)
          then "non-object tokens coerced to zero" else empty end),
       # An object-form tokens whose input/cache_creation/cache_read/output was
       # present but NON-numeric (string/object): coerced to 0 (which also averts
       # the "string and number cannot be added" jq crash) — surface it.
       (if ($e.tokens | type) == "object"
           and ([ ($e.tokens.input), ($e.tokens.cache_creation),
                  ($e.tokens.cache_read), ($e.tokens.output) ]
                | map(select((. != null) and (type != "number"))) | length) > 0
          then "non-numeric token field coerced to zero" else empty end),
       (if ($tk._stated_processed != null) and ($tk._stated_processed != $tk.processed)
          then "stated processed \($tk._stated_processed) != derived \($tk.processed)" else empty end),
       (if ($e.attempt_id != null) and (($e.attempt_id | type) != "string")
          then "non-string attempt_id isolated to a synthetic key" else empty end),
       (if ($e.agent_id   != null) and (($e.agent_id   | type) != "string")
          then "non-string agent_id isolated to a synthetic key" else empty end),
       # session_id / spawn_id: extend _norm_note coverage (AC-5). A present-but-
       # wrong-typed session_id/spawn_id isolates to a synthetic key and is surfaced
       # (the F1 vector: an object spawn_id on a reviewer).
       (if ($e.session_id != null) and (($e.session_id | type) != "string")
          then "non-string session_id isolated to a synthetic key" else empty end),
       (if ($e.spawn_id   != null) and (($e.spawn_id   | type) != "string")
          then "non-string spawn_id isolated to a synthetic key" else empty end),
       # FR 5 (D): absent-required-id isolation breadcrumbs (never silent). Fires
       # only when the field was in $required AND the computed id is a synthetic key.
       (if (($required | index("attempt_id")) != null)
            and (($aid | type) == "string") and ($aid | startswith("__malformed__attempt_id"))
          then "absent attempt_id isolated to a synthetic key" else empty end),
       (if (($required | index("agent_id")) != null)
            and (($gid | type) == "string") and ($gid | startswith("__malformed__agent_id"))
          then "absent agent_id isolated to a synthetic key" else empty end),
       (if (($required | index("session_id")) != null)
            and (($sid | type) == "string") and ($sid | startswith("__malformed__session_id"))
          then "absent session_id isolated to a synthetic key" else empty end),
       (if (($required | index("spawn_id")) != null)
            and (($pid | type) == "string") and ($pid | startswith("__malformed__spawn_id"))
          then "absent spawn_id isolated to a synthetic key" else empty end),
       # FR 6 / A4: absent tokens field on a token event (never silent).
       (if $tokens_absent
          then "absent tokens field on a token event — not blessed as exact" else empty end)
     ]) as $malformed
  # FR 6 / A6: partial tokens object — detect absent components and processed
  # disagreement from the RAW .tokens object (not $tk, which coerces absent → 0).
  # REUSES $tk._stated_processed and $tk.processed from coerce_tokens (AS 5 reuse).
  # Only fires when $required is non-empty (token streams) AND tokens is an object.
  | (if (($required | length) > 0) and (($e.tokens | type) == "object")
     then
       ([ "input","cache_creation","cache_read","output" ]
        | map(select((($e.tokens[.] // null) | type) != "number"))) as $absent_components
       | (($tk._stated_processed != null)
          and ($tk._stated_processed != $tk.processed)) as $disagreement
       | if (($absent_components | length) > 0) or $disagreement
         then {
           _tokens_partial: true,
           _partial_fields: ($absent_components
             + (if $disagreement then ["processed"] else [] end))
         }
         + { _a6_note: (if ($absent_components | length) > 0
               then "partial tokens object — \($absent_components | length) component(s) absent"
               else "stated processed disagrees with component sum" end) }
         else {}
         end
     else {} end) as $a6_partial
  | ($e | del(.["_ord"]))
    + { tokens: ($tk | del(._stated_processed)),
        turns: $turns, attempt_id: $aid, agent_id: $gid,
        session_id: $sid, spawn_id: $pid }
    # tag the record so the per-stream isolation flags can force any bucket that
    # absorbed it off `exact`. Only added when actually isolated, so a clean record
    # is byte-identical.
    + (if $isolated then { _isolated: true } else {} end)
    # A6 partial fields — additive, not overwriting.
    + (if ($a6_partial | has("_tokens_partial")) then {_tokens_partial: true} else {} end)
    + (if ($a6_partial | has("_partial_fields")) then {_partial_fields: $a6_partial._partial_fields} else {} end)
    # keep the raw _note if the emitter already wrote one (clamp notes etc.);
    # append a normalization breadcrumb (a DISTINCT field, _norm_note, so it never
    # collides with the emitter-written _note the $*_event_notes collectors read)
    # only when we actually coerced/isolated something.
    + (if (($malformed | length) > 0) or ($a6_partial | has("_a6_note"))
       then { _norm_note: ([$malformed[], (if ($a6_partial | has("_a6_note")) then $a6_partial._a6_note else empty end)] | join("; ")) }
       else {} end);

# Rebind the five event streams through the normalizer BY SHADOWING the outer
# $name — from here down every reference to $spawn_events/$spawn_tokens/$conductor/
# $delegate/$reviewers is lexically inside the shadow and reads normalized data, so
# the ~40 downstream read-sites are untouched. This block MUST precede any $started/
# $stok/$cond/$del/$rev binding.
#
# `to_entries | map(.value + {_ord: .key} | normalize_event)` threads the stable
# pre-group array index into each record as `_ord` (which normalize_event embeds in
# any synthetic isolate key and then deletes). The index is taken HERE, BEFORE any
# group_by, so it is unique within the stream — the invariant F1 relies on. On a
# clean stream `_ord` is set then immediately deleted and no synthetic key is minted,
# so the emitted records are byte-identical to `map(normalize_event)`.
($spawn_events | to_entries | map(.value + {_ord: .key} | normalize_event([]))) as $spawn_events
| ($spawn_tokens | to_entries | map(.value + {_ord: .key} | normalize_event(["agent_id","attempt_id"]))) as $spawn_tokens
| ($conductor    | to_entries | map(.value + {_ord: .key} | normalize_event(["session_id"]))) as $conductor
| ($delegate     | to_entries | map(.value + {_ord: .key} | normalize_event(["session_id"]))) as $delegate
| ($reviewers    | to_entries | map(.value + {_ord: .key} | normalize_event(["spawn_id"]))) as $reviewers
# Per-stream isolation flags: true when ANY record in the stream was isolated to a
# synthetic key. AND'd (via `| not`) into each block's confidence gate so a bucket
# that absorbed a malformed/isolated record is NOT blessed as `exact`. On a clean
# corpus all four are false, so every confidence string is byte-identical (AC-11).
| (($reviewers    | map(select(.["_isolated"] == true)) | length) > 0) as $rev_isolated
| (($conductor    | map(select(.["_isolated"] == true)) | length) > 0) as $cond_isolated
| (($delegate     | map(select(.["_isolated"] == true)) | length) > 0) as $del_isolated
| (($spawn_tokens | map(select(.["_isolated"] == true)) | length) > 0) as $spec_isolated
# FIX 1 (cause-accurate block notes): for each stream that has isolated records,
# detect whether the isolation was due to an absent/null tokens field (A4 breadcrumb)
# vs a malformed/absent id (id-cause). Used to branch the block note text so the
# diagnostic names the actual cause instead of always saying "session_id".
| (($conductor | map(select(.["_isolated"] == true)
       | select((._norm_note // "") | test("absent tokens field"))) | length) > 0)
     as $cond_isolated_tokens_absent
| (($delegate  | map(select(.["_isolated"] == true)
       | select((._norm_note // "") | test("absent tokens field"))) | length) > 0)
     as $del_isolated_tokens_absent
| (($reviewers | map(select(.["_isolated"] == true)
       | select((._norm_note // "") | test("absent tokens field"))) | length) > 0)
     as $rev_isolated_tokens_absent

# --- Specialist spawns: started (deduped by attempt_id, first) + terminals ----
| ($spawn_events | map(select(.status == "started")) | group_by(.attempt_id) | map(.[0])) as $started
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
| ($spawn_tokens | group_by(.agent_id) | map(max_by((.tokens | objects | .processed) // 0))) as $stok_by_agent
| ($started | map(.attempt_id)) as $started_ids

# --- F1 (audit): enforce the 1:1 attempt_id → agent_id invariant --------------
# subagent-stop.sh admits a specialist on a MENTION gate (RUN_DIR + Attempt ID in
# the spawn prompt, no identity check), so a foreign/duplicate subagent can log a
# SECOND, distinct agent_id under a real attempt_id. The per-agent_id take-max
# above keeps BOTH (each is a distinct agent_id), and — because both carry a real,
# started attempt_id — the unattributed filter (which only flags null/unknown
# attempt_ids) does NOT catch either. Result: foreign cost summed into a legit
# attempt as "exact". Here we require exactly ONE agent_id per STARTED attempt_id:
# among the records that claim one started attempt_id, keep the max-processed one
# (deterministic; ties break on max processed then it is a single record) and
# route the losers to a suspect set — never sum them. This mirrors the
# timestamp-guard philosophy (distrust the extra, do not silently bless it).
# Records with a null attempt_id, or an attempt_id that is not a started spawn,
# are untouched here — they are already surfaced by the $unattributed filter.
| ($stok_by_agent | group_by(.attempt_id)
   | map(
       # A collision group = a non-null, STARTED attempt_id claimed by >1 record.
       # Bind the group's attempt_id first so the `index()` argument is not
       # re-evaluated against $started_ids as its `.` (a jq indexing pitfall).
       (.[0].attempt_id) as $aid
       | if ($aid != null)
            and (($started_ids | index($aid)) != null)
            and (length > 1)
         then { keep: [ max_by((.tokens | objects | .processed) // 0) ],
                drop: ( (max_by((.tokens | objects | .processed) // 0)) as $w
                        | map(select(.agent_id != $w.agent_id)) ) }
         else { keep: ., drop: [] }
         end)) as $stok_groups
| ($stok_groups | map(.keep) | add // []) as $stok
| ($stok_groups | map(.drop) | add // []) as $stok_collisions
| ($stok | map(.attempt_id) | map(select(. != null))) as $stok_ids
| (if ($stok_collisions | length) > 0
   then ($stok_collisions | group_by(.attempt_id)
         | map("attempt_id \(.[0].attempt_id) claimed by \(length + 1) distinct agent_ids "
               + "(\([.[].agent_id] | join(", "))) — kept the max-processed one, "
               + "routed \(length) extra(s) to unattributed (possible foreign/duplicate subagent under one attempt)")
         | join("; "))
   else null end) as $stok_collision_note

# specialist share (sum over the 1:1 deduped set — foreign duplicates excluded)
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
# Audit r2 (F3): carry each conductor event's own `._note` (e.g. a clamp note from
# compute_delta_line: "clamped input (raw 100 < baseline 999) to 0") from the
# deduped set into the block. The emitters write these correctly; the consumer must
# SURFACE them, never silently drop. Collect over $cond (the take-max set actually
# summed). Joined string, or null if no event carried a note.
| ($cond | map(._note // empty) | if length > 0 then join("; ") else null end) as $cond_event_notes

# --- DELEGATE-TOKEN-EVENT (#26a): mirror of the conductor block ----------------
# Same shape as CONDUCTOR: dedup per session_id take-max on processed, sum across
# legs, same non-object `tokens` tolerance, same leg-final confidence logic. The
# Delegate top session behaves like a single long-lived Conductor session.
| ($delegate | map(select((.tokens | type) != "object")) | length) as $del_nonobj_n
| ($delegate | group_by(.session_id) | map(max_by((.tokens | objects | .processed) // 0))) as $del
| ($delegate | group_by(.session_id) | map(map(.final == true) | any)) as $del_leg_finals
| (($delegate | length) > 0 and ($del_leg_finals | all)) as $all_del_legs_final
| ($del | length) as $del_legs
| ($del | map((.tokens | objects | .input) // 0)          | add // 0) as $del_input
| ($del | map((.tokens | objects | .cache_creation) // 0) | add // 0) as $del_cc
| ($del | map((.tokens | objects | .cache_read) // 0)     | add // 0) as $del_cr
| ($del | map((.tokens | objects | .processed) // 0)      | add // 0) as $del_processed
| ($del | map((.tokens | objects | .output) // 0)         | add // 0) as $del_output
| ($del | map(.turns // 0)                                | add // 0) as $del_turns
# Audit r2 (F3): carry each delegate event's own `._note` (clamp note) — same as conductor.
| ($del | map(._note // empty) | if length > 0 then join("; ") else null end) as $del_event_notes
# Confidence: exact only when all legs final AND not (zero-tokens-with-note). A clamp
# note that rolled the block to zero must NOT be blessed as exact (audit r2 F3): downgrade
# to "partial" (data present but degraded). Carry the note regardless of zero/non-zero;
# downgrade ONLY on the zero-with-note case — a legit non-zero clamp note stays exact.
| (($del_processed == 0) and ($del_event_notes != null)) as $del_zero_with_note
# $del_isolated (a malformed/absent session_id leg isolated to a synthetic key) is
# AND'd into exact too — an isolated leg is a distinct real cost routed to its own
# bucket, so the summed block is no longer trustworthy-as-exact.
| (if $all_del_legs_final and ($del_zero_with_note | not) and ($del_isolated | not) then "exact"
   elif ($delegate | length) > 0 then "partial"
   else "unavailable" end) as $del_conf
| (if ($all_del_legs_final and $del_zero_with_note) then "delegate block rolled up to zero tokens but at least one event carried a _note (a clamp-to-zero or missing-usage fallback) — not blessed as exact"
   elif ($del_isolated and ($delegate | length) > 0)
        and $del_isolated_tokens_absent
     then "one or more delegate record(s) had an absent/null tokens object on a token event — isolated, block not blessed as exact"
   elif ($del_isolated and ($delegate | length) > 0)
     then "one or more delegate record(s) had a malformed/absent session_id — isolated to a distinct synthetic bucket, block not blessed as exact"
   elif $del_conf == "partial" then "final-leg-capture-pending: post-close-out Stop hook has not yet fired for the Delegate top session"
   elif $del_conf == "unavailable" then "no DELEGATE-TOKEN-EVENT lines present in log.md yet"
   else null end) as $del_block_note

# --- REVIEWER-TOKEN-EVENT (#26b): dedup per spawn_id take-max, SUM all spawns --
# Each cold reviewer is a fresh one-shot — no leg/final/baseline concept. Dedup on
# spawn_id (defensive against a torn re-log) then SUM across ALL spawn_ids (every
# reviewer spawn is a distinct cost). Same non-object `tokens` tolerance.
| ($reviewers | map(select((.tokens | type) != "object")) | length) as $rev_nonobj_n
| ($reviewers | group_by(.spawn_id) | map(max_by((.tokens | objects | .processed) // 0))) as $rev
| ($rev | length) as $rev_spawns
| ($rev | map((.tokens | objects | .input) // 0)          | add // 0) as $rev_input
| ($rev | map((.tokens | objects | .cache_creation) // 0) | add // 0) as $rev_cc
| ($rev | map((.tokens | objects | .cache_read) // 0)     | add // 0) as $rev_cr
| ($rev | map((.tokens | objects | .processed) // 0)      | add // 0) as $rev_processed
| ($rev | map((.tokens | objects | .output) // 0)         | add // 0) as $rev_output
| ($rev | map(.turns // 0)                                | add // 0) as $rev_turns
# Audit r2 (F2): carry each reviewer event's own `._note` — append-reviewer-tokens.sh
# writes one on a `.usage`-less envelope ("reviewer envelope had no .usage block …").
# The consumer must SURFACE it, never drop. Collect over $rev (the summed set).
| ($rev | map(._note // empty) | if length > 0 then join("; ") else null end) as $rev_event_notes
# Each one-shot is complete by construction, so a present reviewer line is exact —
# UNLESS the block rolled up to zero tokens AND at least one event carried a _note (a
# missing-usage fallback): a zero-washed-as-exact is exactly the bug (audit r2 F2).
# Downgrade to "partial" only on the zero-with-note case; a legit non-zero block with
# no note stays "exact" byte-unchanged.
| (($rev_processed == 0) and ($rev_event_notes != null)) as $rev_zero_with_note
# $rev_isolated (a malformed/absent spawn_id record isolated to a synthetic key —
# the F1 vector) is AND'd in too: a block that absorbed an isolated reviewer must
# NOT read exact (the isolated spawn is a distinct real cost that was routed to its
# own bucket, so the block is no longer a complete, trustworthy sum).
| (if ($reviewers | length) > 0 and ($rev_zero_with_note | not) and ($rev_isolated | not) then "exact"
   elif ($reviewers | length) > 0 then "partial"
   else "unavailable" end) as $rev_conf
| (if ($rev_zero_with_note and ($reviewers | length) > 0) then "reviewer block rolled up to zero tokens but at least one event carried a _note (a missing-usage fallback) — not blessed as exact"
   elif ($rev_isolated and ($reviewers | length) > 0)
        and $rev_isolated_tokens_absent
     then "one or more reviewer record(s) had an absent/null tokens object on a token event — isolated, block not blessed as exact"
   elif ($rev_isolated and ($reviewers | length) > 0)
     then "one or more reviewer record(s) had a malformed/absent spawn_id — isolated to a distinct synthetic bucket, block not blessed as exact"
   elif $rev_conf == "unavailable" then "no REVIEWER-TOKEN-EVENT lines present in log.md yet"
   else null end) as $rev_block_note

# --- F3 (audit): re-derive `processed`, do not trust the field verbatim -------
# Bug 3: the consumer summed each event's `processed` field as-authored, so a
# forged / mis-composed line whose stated `processed` disagrees with its own
# input+cache_creation+cache_read went unchecked. A hook-emitted event always
# satisfies processed == input+cache_creation+cache_read (built that way in
# bureau-token-lib.sh), so this never fires on a real event. The normalization
# pass now DERIVES processed authoritatively at ingest (the summed value is
# already the component sum), but the identity NOTE must still fire so a forged/
# mis-composed line is visible. Re-source it from the pass: an event whose
# `_norm_note` records a "stated processed … != derived" disagreement is a
# mismatch. Scanned over the two sets that feed processed_total — the 1:1
# specialist set $stok and the conductor set $cond.
| ([ ($stok[]?), ($cond[]?) ]
   | map(select((._norm_note // "") | test("stated processed"))))
     as $processed_mismatch
| (($processed_mismatch | length) > 0) as $processed_identity_bad
| (if $processed_identity_bad
   then "\($processed_mismatch | length) token event(s) have a `processed` that disagrees with input+cache_creation+cache_read — the component sum is authoritative, the stated `processed` is not trusted verbatim"
   else null end) as $processed_identity_note

# --- processed_total + confidence lattice (FR 9 / FR 10) ----------------------
# processed_total stays BUILD-ONLY (spec + conductor). The Delegate/reviewer
# gating cost is NOT build rework, so folding it into the rework_ratio /
# tokens_per_loop denominator would distort those ratios — it lives in its own
# blocks instead. output_total (below) DOES fold all four roles (it is a raw
# total, not a ratio denominator). [OQ-1: Conductor decision — build-only.]
| ($spec_processed + $cond_processed) as $processed_total
| ($all_legs_final) as $cond_ok
| ($n_unmatched == 0) as $spec_ok
# A malformed attempt_id/agent_id in the specialist set already routes to
# $unattributed and is excluded from $spec_processed, so the NUMBER is safe — but a
# block that isolated a specialist record must not read exact, so fold $spec_isolated
# (and, for the conductor share, $cond_isolated) into the processed_total gate.
| (if $cond_ok and $spec_ok and ($spec_isolated | not) and ($cond_isolated | not) then "exact" else "partial" end) as $pt_conf
| ([ (if ($cond_ok | not) then "conductor-share-pending: final-leg capture not yet in log.md" else empty end),
     (if ($spec_ok | not) then "\($n_unmatched) specialist spawn(s) have no matched SPAWN-TOKEN-EVENT" else empty end),
     (if $spec_isolated then "one or more specialist record(s) had a malformed attempt_id/agent_id — isolated to a distinct synthetic key and routed to unattributed; processed_total not blessed as exact" else empty end),
     (if $cond_isolated and $cond_isolated_tokens_absent
        then "one or more conductor record(s) had an absent/null tokens object on a token event — isolated; processed_total not blessed as exact"
        elif $cond_isolated
        then "one or more conductor record(s) had a malformed/absent session_id — isolated to a distinct synthetic key; processed_total not blessed as exact"
        else empty end),
     (if $processed_identity_note != null then $processed_identity_note else empty end)
   ]) as $pt_notes

# conductor_tokens block confidence
# Audit r2 (F3): a clamp `_note` (e.g. all fields clamped to 0) that rolls the block
# to zero tokens must NOT wear "exact" — downgrade to "partial" (data present but
# degraded). Carry the event note regardless; downgrade ONLY on the zero-with-note
# case, so a legit non-zero clamp note stays "exact" and byte-unchanged.
| (($cond_processed == 0) and ($cond_event_notes != null)) as $cond_zero_with_note
# $cond_isolated (a malformed/absent session_id leg isolated to a synthetic key) is
# AND'd into exact — an isolated leg is a distinct real cost routed to its own bucket.
| (if $all_legs_final and ($cond_zero_with_note | not) and ($cond_isolated | not) then "exact"
   elif ($conductor | length) > 0 then "partial"
   else "unavailable" end) as $cond_conf
| (if ($all_legs_final and $cond_zero_with_note) then "conductor block rolled up to zero tokens but at least one event carried a _note (a clamp-to-zero or missing-usage fallback) — not blessed as exact"
   elif ($cond_isolated and ($conductor | length) > 0)
        and $cond_isolated_tokens_absent
     then "one or more conductor record(s) had an absent/null tokens object on a token event — isolated, block not blessed as exact"
   elif ($cond_isolated and ($conductor | length) > 0)
     then "one or more conductor record(s) had a malformed/absent session_id — isolated to a distinct synthetic bucket, block not blessed as exact"
   elif $cond_conf == "partial" then "final-leg-capture-pending: post-close-out Stop hook has not yet fired for this run"
   elif $cond_conf == "unavailable" then "no CONDUCTOR-TOKEN-EVENT lines present in log.md yet"
   else null end) as $cond_block_note

# --- FR 5: suspicious-multi-leg note (more legs than recorded resumes explain) -
| ($legs > ($resumed_legs + 1)) as $suspicious_multi_leg
| (if $suspicious_multi_leg
   then "\($legs) conductor legs detected with no resume evidence in state.json — verify all are legitimate conductor legs; a foreign session may have been captured."
   else null end) as $suspicious_note

# --- Topology-agnostic zero-conductor gate (FR 4) ----------------------------
# Fires whenever $cond_conf == "unavailable" (zero CONDUCTOR-TOKEN-EVENT lines),
# regardless of topology. Two sub-cases distinguish protocol failure from a
# capture that is legitimately still pending:
#   - No "Pointer enrolled" line in log.md → run-start.sh never enrolled the
#     pointer; zero conductor events is a protocol failure, not a clean zero.
#   - "Pointer enrolled" line present → pointer was enrolled; the Stop hook has
#     not yet fired (close-out still in flight, or the run is pending).
# The pointer_enrolled signal is pre-computed in bash (grep, PATH-pinned) and
# passed as a jq --arg so the gate is ugrep-immune (EC 10).
| (if ($cond_conf == "unavailable") then
    (if $pointer_enrolled == "no"
     then "protocol failure — pointer enrolment never ran; zero CONDUCTOR-TOKEN-EVENT is not a clean zero"
     else "capture still pending — close-out Stop hook not yet fired; CONDUCTOR-TOKEN-EVENT not captured"
     end)
   else null end) as $zero_conductor_note

# --- #26 sibling gap-notes (independent of the conductor gap; same pattern) ----
# Delegate gap: integrated topology but zero DELEGATE-TOKEN-EVENT → the Delegate's
# own pointer/emission did not fire. Reviewer gap: integrated topology with >=1
# RESOLVED checkpoint but zero REVIEWER-TOKEN-EVENT → the Delegate did not append
# reviewer usage. The reviewer gap is gated on >=1 resolved checkpoint so a v2 run
# that has not hit a checkpoint yet does not false-fire. Annotate only — never
# fabricate a number, never change confidence (already "unavailable", correct).
| ($checkpoints | map(select(.status == "resolved")) | length) as $resolved_cp_n
| (if ($delegate_topology == "integrated") and ($del_conf == "unavailable")
   then "v2-integrated topology but zero DELEGATE-TOKEN-EVENT captured — the Delegate's own pointer/emission did not fire (check the role:delegate pointer enrolment in agents/delegate.md § Bootstrap and the conductor-stop.sh role branch); Delegate-manager share is a real gap, not a clean zero"
   else null end) as $del_gap_note
| (if ($delegate_topology == "integrated") and ($rev_conf == "unavailable") and ($resolved_cp_n > 0)
   then "v2-integrated topology with \($resolved_cp_n) resolved checkpoint(s) but zero REVIEWER-TOKEN-EVENT captured — the Delegate did not append reviewer usage (check agents/delegate.md step 6.5 + scripts/append-reviewer-tokens.sh); reviewer share is a real gap, not a clean zero"
   else null end) as $rev_gap_note

# --- FR 5: merge cond-block note + suspicious note + zero-conductor note (can co-fire) --
# Audit r2 (F3): $cond_event_notes (each event's own clamp `_note`) is folded in here
# too, so a clamp warning SURFACES on the block instead of being silently dropped.
| ([
    (if $cond_block_note != null then $cond_block_note else empty end),
    (if $cond_event_notes != null then $cond_event_notes else empty end),
    (if $suspicious_note != null then $suspicious_note else empty end),
    (if $zero_conductor_note != null then $zero_conductor_note else empty end)
  ] | if length > 0 then join("; ") else null end) as $combined_note

# Merge each sibling block's own note with its gap note AND its event-level `_note`s
# (audit r2 F2/F3) — each on its OWN block, each surfaced.
| ([ (if $del_block_note  != null then $del_block_note  else empty end),
     (if $del_event_notes != null then $del_event_notes else empty end),
     (if $del_gap_note    != null then $del_gap_note    else empty end)
   ] | if length > 0 then join("; ") else null end) as $del_combined_note
| ([ (if $rev_block_note  != null then $rev_block_note  else empty end),
     (if $rev_event_notes != null then $rev_event_notes else empty end),
     (if $rev_gap_note    != null then $rev_gap_note    else empty end)
   ] | if length > 0 then join("; ") else null end) as $rev_combined_note

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
# OQ-2 (the F1 sibling): checkpoints group_by(.id) and pair raised↔resolved on .id.
# A malformed (non-string) checkpoint .id would group_by(null) and collapse two
# distinct malformed checkpoints into one (same failure as F1's spawn_id), and a
# malformed id feeding a downstream object key could crash. Apply the SAME isolate
# primitive: a PRESENT-but-wrong-typed .id → a distinct synthetic string key
# `__malformed__id__<ord>` (ord = pre-group index, taken here before any group_by so
# it is unique); an absent/valid-string id is kept verbatim (byte-identity on valid
# input — a clean checkpoint corpus is unchanged). Lower stakes than the token streams
# (wait_s, not token cost), so no confidence downgrade — just no-collapse + no-crash.
| ($checkpoints
   | to_entries
   | map(.value
         + {id: (if (.value.id | type) == "string" and (.value.id != "")
                     then .value.id
                   elif (.value.id == null) or (.value.id == "")
                     then "__malformed__id__\(.key)"
                   else "__malformed__id__\(.key)" end)})) as $checkpoints
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
# The null/unknown-attempt_id records PLUS the F1 collision losers (the extra
# agent_ids that claimed a started attempt_id already owned by another record —
# surfaced here so their cost is visible and NOT silently blessed as exact).
| (($stok | map(. as $r | select(($r.attempt_id == null) or (($started_ids | index($r.attempt_id)) == null))))
   + $stok_collisions) as $unattributed

# --- spawn_tokens map keyed by attempt_id (for account-run.sh Step 6.6) -------
# §1.3 (F3): the reduce keys on $sp.attempt_id. Two guards on the input $pairs:
#   1. `select(.attempt_id != null)` — defensive: even a future path that reintroduces
#      a null key SKIPS rather than throwing "Cannot use null as object key".
#   2. `select((.attempt_id | startswith("__malformed__")) | not)` — a started spawn
#      whose attempt_id was isolated to a synthetic key must NOT be published as a real
#      spawn_tokens map entry (account-run.sh's STEP A2 would pair it to a specialist
#      row). It contributes 0 to the map, is noted, and is already surfaced via
#      $unattributed / $norm_events. (On a clean corpus every attempt_id is a real
#      string that does not start with "__malformed__", so the filter is a no-op and
#      the map is byte-identical.)
| (reduce ($pairs[]
          | select(.attempt_id != null)
          | select((.attempt_id | startswith("__malformed__")) | not)) as $sp ({};
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
            # FR 6 / A6: carry _partial_fields from the normalized record so
            # account-run.sh's with_entries confidence projection can read $stk._partial_fields.
            _partial_fields: (if $tok != null then ($tok._partial_fields // null) else null end),
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
      output_total: {value: ($spec_output + $cond_output + $del_output + $rev_output), confidence: "estimated"},
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
    delegate_tokens: ({
      tokens: {input: $del_input, cache_creation: $del_cc, cache_read: $del_cr, processed: $del_processed, output: $del_output},
      turns: $del_turns,
      legs: $del_legs,
      confidence: $del_conf
    } + (if $del_combined_note != null then {_note: $del_combined_note} else {} end)),
    reviewer_tokens: ({
      tokens: {input: $rev_input, cache_creation: $rev_cc, cache_read: $rev_cr, processed: $rev_processed, output: $rev_output},
      turns: $rev_turns,
      spawns: $rev_spawns,
      confidence: $rev_conf
    } + (if $rev_combined_note != null then {_note: $rev_combined_note} else {} end)),
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
  # Merge torn-line parse notes with the normalization advisory (both land in
  # _notes). The normalization pass records a `_norm_note` on any event whose
  # `tokens` was a non-object (scalar), whose numeric field was a string/object,
  # or whose attempt_id/agent_id was a non-string — each coerced/isolated to a
  # safe value instead of crashing the pass (F2). Count them across ALL FIVE
  # normalized sets so a malformed event in any role bucket is surfaced, not
  # silently swallowed. (The old per-block $*_nonobj_n counters now see the
  # NORMALIZED set — always an object — so they read 0; this is the re-sourced
  # replacement.)
  | ([ $spawn_events[]?, $spawn_tokens[]?, $conductor[]?, $delegate[]?, $reviewers[]? ]
      | map(select(has("_norm_note")))) as $norm_events
  | ($norm_events | length) as $norm_total
  # Extra _notes breadcrumbs beyond the torn-line parse notes: the normalization
  # advisory, the F1 attempt_id→agent_id collision note, and the F3
  # processed-identity mismatch note — each surfaced so a reader sees it, never
  # silently swallowed. All conditional, so a clean run adds no _notes key.
  | ([ (if $norm_total > 0
        then "\($norm_total) token event(s) had a malformed field (non-object tokens / non-numeric numeric / non-string id) — coerced/isolated to safe values, not fatal"
        else empty end),
       (if $stok_collision_note != null then $stok_collision_note else empty end),
       (if $processed_identity_note != null then $processed_identity_note else empty end)
     ]) as $extra_notes
  | . + (if (($parse_notes | length) > 0) or (($extra_notes | length) > 0)
         then {_notes: ($parse_notes + $extra_notes)}
         else {} end)
  # Advisory stderr line (nice-to-have): mirrors account-run.sh's WARNING lane.
  # `debug` writes ["DEBUG:", …] to STDERR and passes its input through unchanged
  # on stdout, so the single-value JSON fragment account-run.sh captures is
  # untouched. Gated on $norm_total so a clean run emits nothing.
  | if $norm_total > 0
    then debug("[account-tokens] NOTE: coerced/isolated \($norm_total) malformed token event(s)")
    else . end
JQ
)

# --- FR 4: pre-compute pointer-enrolled signal (ugrep guard) ------------------
# grep is PATH-pinned so ugrep (which may be aliased as grep on this machine)
# does not produce a false-negative for a boundary pattern (EC 10).
PATH=/usr/bin:$PATH
_pointer_enrolled_line="Pointer enrolled — nonce written to pointer file"
if grep -qF "$_pointer_enrolled_line" "$RUN_DIR/log.md" 2>/dev/null; then
  _pointer_enrolled="yes"
else
  _pointer_enrolled="no"
fi

if jq -n \
  --slurpfile spawn_events "$se_f" \
  --slurpfile spawn_tokens "$st_f" \
  --slurpfile conductor "$ct_f" \
  --slurpfile delegate "$de_f" \
  --slurpfile reviewers "$rv_f" \
  --slurpfile checkpoints "$cp_f" \
  --slurpfile parse_notes "$nt_f" \
  --argjson critic_loops "$critic_loops_json" \
  --argjson resumed_legs "$resumed_legs" \
  --arg delegate_topology "$delegate_topology" \
  --arg pointer_enrolled "$_pointer_enrolled" \
  "$JQ_PROG"; then
  exit 0
else
  echo "[account-tokens] jq failed to assemble metrics for $RUN_DIR" >&2
  exit 1
fi
