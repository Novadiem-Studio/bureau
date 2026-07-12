#!/usr/bin/env bash
# subagent-stop.sh — Claude Code SubagentStop hook (Bundle 11, Phase 2).
#
# Fires when each Task subagent completes. Reads the subagent's isolated
# transcript, extracts deduped token usage, and appends one token event to the
# active bureau run's log.md:
#   - a SPAWN-TOKEN-EVENT for a normal specialist subagent (default), OR
#   - a CONDUCTOR-TOKEN-EVENT (baseline/delta) when the spawn prompt carries the
#     `BUREAU_ROLE: conductor` marker — the v2-integrated case where the Conductor
#     runs as an Agent-tool subagent of the Delegate (see Step 4.5 + the Conductor
#     branch). The delta arithmetic is shared with conductor-stop.sh via
#     bureau-token-lib.sh (compute_delta_line / compute_legacy_line).
#
# CRITICAL: This hook fires for EVERY Claude Code session on this machine,
# including non-bureau subagents. Non-bureau sessions exit 0 silently via
# the fail-safe ladder below. A crash or non-zero exit here would disrupt
# unrelated work — all own-errors log to stderr and exit 0.
#
# Fail-safe ladder (checked in order; first failure → exit 0):
#   1. agent_transcript_path field present and non-empty
#   2. Transcript file exists and is readable
#   3. First user message contains "RUN_DIR: <path>" (bureau identity check)
#   4. RUN_DIR exists as a directory AND RUN_DIR/log.md is a readable file
#
# Field names confirmed in docs/run-accounting.md § "Hook field names
# (Bundle 11 ground truth)": agent_transcript_path, agent_id.
#
# Portability: Bash 3.2 + jq on macOS. No set -e (hooks must always
# exit 0); errors are logged to stderr. No associative arrays, no GNU-only
# date flags.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helper: read stdin JSON once ────────────────────────────────────────────
stdin_json=$(cat)

# ── Step 1: Extract transcript path ─────────────────────────────────────────
# Confirmed field name: agent_transcript_path (docs/run-accounting.md ground truth)
transcript_path=$(printf '%s' "$stdin_json" | jq -r '.agent_transcript_path // empty' 2>/dev/null)
if [ -z "$transcript_path" ]; then
  exit 0  # Not a subagent with a transcript — silent no-op
fi

# ── Step 2: Verify transcript is readable ───────────────────────────────────
if [ ! -r "$transcript_path" ]; then
  echo "[subagent-stop] transcript not readable: $transcript_path" >&2
  exit 0
fi

# ── Step 3: Extract RUN_DIR from first user message ─────────────────────────
# The first user-role JSONL line is the spawn prompt; bureau spawns always
# include "RUN_DIR: <abs path>" in that prompt.
# Use -Rn + fromjson? to skip malformed lines gracefully.
#
# Real Claude Code transcript schema (Bundle 11 ground truth — confirmed 2026-07-05):
#   {"type":"user","message":{"role":"user","content":"<string or array>"}}
# Top-level .role is absent; the selector must match on .type == "user" and
# read .message.content. The old .role? == "user" selector matched ZERO lines
# in production transcripts (silent no-op blocker — Challenger-verified).
first_user_content=$(jq -Rn '
  [inputs | fromjson?]
  | map(select(.type? == "user"))
  | if length > 0 then .[0].message.content else "" end
' "$transcript_path" 2>/dev/null) || first_user_content='""'

# first_user_content is a JSON value (may be a string, array, or null).
# Normalise to a plain text string.
first_user_text=$(printf '%s' "$first_user_content" | jq -r 'if type == "string" then . elif type == "array" then map(.text? // "") | join("") else "" end' 2>/dev/null) || first_user_text=""

# Extract the RUN_DIR line value
run_dir=""
if printf '%s' "$first_user_text" | grep -q 'RUN_DIR:'; then
  run_dir=$(printf '%s' "$first_user_text" | grep 'RUN_DIR:' | head -1 | sed 's/.*RUN_DIR:[[:space:]]*//' | tr -d '\r')
fi

if [ -z "$run_dir" ]; then
  exit 0  # Not a bureau subagent — silent no-op
fi

# ── Step 4: Verify RUN_DIR and log.md exist ──────────────────────────────────
if [ ! -d "$run_dir" ] || [ ! -r "$run_dir/log.md" ]; then
  exit 0  # Run archived or cleaned up — silent no-op
fi

# ── Step 4.5: Classify — is this the Conductor subagent? ─────────────────────
# In a v2-integrated (Delegate-driven) run the Conductor executes as an
# Agent-tool subagent of the Delegate. The Delegate's spawn prompt marks it with
# a `BUREAU_ROLE: conductor` line (agents/delegate.md § Bootstrap). Classify off
# that marker so the Conductor's spend is emitted as a CONDUCTOR-TOKEN-EVENT
# (baseline/delta, like conductor-stop.sh) instead of a SPAWN-TOKEN-EVENT.
#
# Detection is ANCHORED-EXACT (^\s*BUREAU_ROLE:\s+conductor\s*$, case-sensitive):
# a specialist prompt that merely mentions the word "conductor" in prose does NOT
# match — it is not a BUREAU_ROLE: line. BUREAU_ROLE: is a new token used by no
# specialist spawn prompt (they carry `Role mode:` / `Attempt ID:`), so a plain
# Analyst/Challenger/Mage/etc. subagent can never be misclassified. Absence of
# the marker ⇒ the unchanged SPAWN-TOKEN-EVENT path below.
is_conductor="false"
if printf '%s' "$first_user_text" \
   | grep -qE '^[[:space:]]*BUREAU_ROLE:[[:space:]]+conductor[[:space:]]*$'; then
  is_conductor="true"
fi

# ── Step 5: Extract Attempt ID ──────────────────────────────────────────────
attempt_id_raw=""
if printf '%s' "$first_user_text" | grep -q 'Attempt ID:'; then
  attempt_id_raw=$(printf '%s' "$first_user_text" | grep 'Attempt ID:' | head -1 | sed 's/.*Attempt ID:[[:space:]]*//' | tr -d '\r')
fi

if [ -n "$attempt_id_raw" ]; then
  attempt_note=""
else
  attempt_note="attempt_id absent from spawn prompt — record cannot be paired to a SPAWN-EVENT"
fi

# ── Step 6: Extract agent_id from stdin ─────────────────────────────────────
# Confirmed field name: agent_id (docs/run-accounting.md ground truth)
agent_id=$(printf '%s' "$stdin_json" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
if [ -z "$agent_id" ]; then
  # Fallback: derive from transcript basename (agent-<agent_id>.jsonl)
  basename_val=$(basename "$transcript_path" .jsonl)
  agent_id="${basename_val#agent-}"
fi
if [ -z "$agent_id" ]; then
  agent_id="unknown"
fi

# ── Step 7: Sum transcript usage ─────────────────────────────────────────────
# Source the shared library (line-tolerant: malformed JSONL lines are skipped)
# shellcheck source=lib/bureau-token-lib.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bureau-token-lib.sh"

usage_json=""
usage_json=$(sum_transcript_usage "$transcript_path" 2>/dev/null) || usage_json=""

if [ -z "$usage_json" ]; then
  # sum_transcript_usage returned empty — tokens unavailable (fail-safe)
  # Still emit the event with zero tokens so the record is not silently lost
  usage_json='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}'
  echo "[subagent-stop] WARNING: sum_transcript_usage returned empty for $transcript_path — emitting zero-token event" >&2
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Step 8: Compose the event line — fork on the Step 4.5 classification ──────
if [ "$is_conductor" = "true" ]; then
  # ── Step 8.0: Conductor ownership gate (Finding 1 — audit round 2) ──────────
  # The `BUREAU_ROLE: conductor` marker (Step 4.5) is a PUBLIC anchored line in the
  # Delegate's spawn prompt. On its own it proves nothing: a foreign transcript that
  # merely carries `RUN_DIR: <this run>` + `BUREAU_ROLE: conductor` (both public,
  # both echo-able) would be attributed as the Conductor — the dominant cost bucket.
  # The #27 nonce gate (Step 4.7) is SPECIALIST-ONLY and never reached here, so this
  # branch was ungated. Close it with the exact conductor credential.
  #
  # Credential = delegate-state.json#conductor_agent_id (written by agents/delegate.md
  # step 2, immediately after it spawns the Conductor subagent; an archived v2 run
  # shows "conductor_agent_id":"a99267bdd8d314cc3"). NOT the run nonce: the Delegate's
  # conductor spawn prompt has NO `Run nonce:` line, and the run nonce is shared across
  # specialists — a nonce grep would FALSE-REJECT the real Conductor. conductor_agent_id
  # is the one field that names THIS subagent's own agent_id (already read at Step 6).
  #
  # Three states (mirror the #27 specialist gate's pointer-existence carve-out):
  #   1. delegate-state.json present, readable, non-empty .conductor_agent_id →
  #      the gate is CLOSED: our own $agent_id MUST equal it. Equal → proceed.
  #      Differ → FOREIGN: emit NOTHING (no CONDUCTOR event, and do NOT fall through
  #      to attribute as a specialist either), stderr note + exit 0.
  #   2/3. delegate-state.json ABSENT / unreadable / lacks conductor_agent_id (a
  #      legacy / pre-v2 run — which has no conductor-subagent to impersonate anyway)
  #      → fail-OPEN: proceed as today. A missing credential must not reject the one
  #      real capture path a legacy run has. The distinguisher is credential EXISTENCE,
  #      never "$agent_id mismatch", so a foreigner cannot force the carve-out.
  _cond_expected_agent_id=""
  if [ -r "$run_dir/delegate-state.json" ]; then
    _cond_expected_agent_id=$(jq -r '.conductor_agent_id // empty' "$run_dir/delegate-state.json" 2>/dev/null) || _cond_expected_agent_id=""
  fi
  if [ -n "$_cond_expected_agent_id" ]; then
    # State 1 — gate CLOSED. Require identity match.
    if [ "$agent_id" != "$_cond_expected_agent_id" ]; then
      echo "[subagent-stop] conductor ownership gate: agent_id '$agent_id' != delegate-state.json conductor_agent_id '$_cond_expected_agent_id' for RUN_DIR $run_dir — not attributing as Conductor (foreign transcript carrying only the public BUREAU_ROLE marker)" >&2
      exit 0
    fi
  else
    # State 2/3 — no conductor_agent_id credential (legacy/pre-v2 run) → fail-open.
    echo "[subagent-stop] conductor ownership gate: no conductor_agent_id in delegate-state.json for RUN_DIR $run_dir — attributing by marker (pre-v2/legacy run fail-open)" >&2
  fi

  # ═════════════════════════════════════════════════════════════════════════
  #  CONDUCTOR BRANCH — emit a CONDUCTOR-TOKEN-EVENT (baseline/delta), not a
  #  SPAWN-TOKEN-EVENT. The Conductor subagent is resumed at every checkpoint,
  #  so SubagentStop fires MULTIPLE times for the same agent_id, each reading
  #  the CUMULATIVE subagent transcript. Summing raw cumulative each leg would
  #  repeat cache_read across legs (an exact-wash overcount). So each leg emits
  #  a DELTA from a per-agent baseline, exactly as conductor-stop.sh does across
  #  its resumed sessions. The delta arithmetic is the shared compute_delta_line
  #  / compute_legacy_line in bureau-token-lib.sh (one source of truth).
  #
  #  session_id: the emitted CONDUCTOR-TOKEN-EVENT uses agent_id as its
  #  session_id VALUE. agent_id is stable per-subagent across all resumed legs,
  #  so account-tokens.sh's dedup-by-session_id take-max collapses every leg to
  #  the single largest cumulative delta → no cross-leg double-count. (Do NOT
  #  substitute the parent session_id — it would collide across sibling
  #  subagents. OQ-2 resolved by design.)
  #  final: read RUN_DIR/state.json#accounting.status, same signal conductor-stop
  #  uses; missing/unreadable/unparseable ⇒ OPEN (final:false), never a false close.

  # Read closure evidence (fail-safe open).
  final="false"
  if [ -r "$run_dir/state.json" ]; then
    accounting_status=$(jq -r '.accounting.status // empty' "$run_dir/state.json" 2>/dev/null) || accounting_status=""
    if [ -n "$accounting_status" ] && [ "$accounting_status" != "pending" ]; then
      final="true"
    fi
  fi

  # ── Baseline store: RUN_DIR/.conductor-subagent-baseline.json ──────────────
  # A hook-owned dotfile inside the run dir (which .bureau/runs/ already
  # gitignores). NOT the pointer, NOT a state file — no single-writer invariant
  # to break (the hook is the sole writer AND reader). A top-level object keyed
  # by agent_id, so a rare second Conductor subagent (dead-subagent recovery →
  # new agent_id) gets its own baseline slot and is correctly a fresh first leg.
  #
  # Two-row state machine (mirror of conductor-stop.sh Step E.5, minus the
  # legacy and EC-4 rows — a subagent Conductor keeps ONE stable agent_id, so
  # the key never changes within a run, and there is no pre-existing file to be
  # backward-compatible with):
  #   file absent OR key <agent_id> absent  → FIRST LEG: record baseline =
  #        current cumulative, write back (two-step guard), use it (delta ≈ 0).
  #        Write fails → baseline = 0 this leg, no retry (EC-3 degrade: emit raw
  #        cumulative once; a later successful leg emits a delta; take-max keeps
  #        the larger, matching conductor-stop's accepted EC-3 residual).
  #   key present, object  → LATER LEG: reuse verbatim, subtract per field,
  #        clamp ≥ 0, re-derive processed. No write.
  BASELINE_FILE="${BUREAU_SUBAGENT_BASELINE_FILE:-$run_dir/.conductor-subagent-baseline.json}"

  cond_baseline_is_legacy="true"   # true also covers the EC-3 write-fail degrade
  cond_b_input=0; cond_b_cache_creation=0; cond_b_cache_read=0
  cond_b_output=0; cond_b_turns=0
  cond_baseline_obj=""

  # Compose a candidate baseline object from the current cumulative (usage_json).
  _cond_bl_candidate() {
    printf '%s' "$usage_json" | jq -c --arg sid "$agent_id" \
      '{session_id: $sid, input: .input, cache_creation: .cache_creation,
        cache_read: .cache_read, processed: .processed, output: .output, turns: .turns}' \
      2>/dev/null
  }

  # Adopt a just-recorded candidate as the in-memory baseline (delta ≈ 0 this leg).
  _cond_bl_adopt() {
    cond_b_input=$(printf '%s' "$usage_json" | jq -r '.input // 0' 2>/dev/null)
    cond_b_cache_creation=$(printf '%s' "$usage_json" | jq -r '.cache_creation // 0' 2>/dev/null)
    cond_b_cache_read=$(printf '%s' "$usage_json" | jq -r '.cache_read // 0' 2>/dev/null)
    cond_b_output=$(printf '%s' "$usage_json" | jq -r '.output // 0' 2>/dev/null)
    cond_b_turns=$(printf '%s' "$usage_json" | jq -r '.turns // 0' 2>/dev/null)
  }

  # Two-step write-back guard: merge the <agent_id> key into the file (preserving
  # any other agent's slot) via temp-file + atomic mv beside the file. Failure
  # (mktemp/jq/mv) → return 1; caller degrades to baseline = 0 this leg, no retry.
  # $1 = candidate baseline object JSON.
  _cond_bl_write_back() {
    local cand="$1" existing tmp_bl
    [ -n "$cand" ] || return 1
    if [ -r "$BASELINE_FILE" ]; then
      existing=$(cat "$BASELINE_FILE" 2>/dev/null)
      # Non-object / empty existing content → start fresh from {}.
      printf '%s' "$existing" | jq -e 'type == "object"' >/dev/null 2>&1 || existing="{}"
    else
      existing="{}"
    fi
    tmp_bl=$(mktemp "${BASELINE_FILE}.tmp.XXXXXX" 2>/dev/null) || return 1
    if ! printf '%s' "$existing" | jq -c --arg aid "$agent_id" --argjson cand "$cand" \
          '. + {($aid): $cand}' > "$tmp_bl" 2>/dev/null; then
      rm -f "$tmp_bl" 2>/dev/null
      return 1
    fi
    if ! mv "$tmp_bl" "$BASELINE_FILE" 2>/dev/null; then
      rm -f "$tmp_bl" 2>/dev/null
      return 1
    fi
    return 0
  }

  # Read the recorded baseline object for THIS agent_id (empty if absent).
  #
  # F5 (audit): a baseline slot that is a valid JSON object but carries a
  # WRONG-TYPE numeric field (e.g. {"input":"oops",...}) must be treated as
  # ABSENT — not reused. Reused, `.input // 0` yields "oops" (jq `//` catches
  # null/false, NOT a wrong type), and compute_delta_line's `--argjson b_input
  # "oops"` is invalid JSON → the compose fails → zero events appended and the
  # corrupt baseline LEFT INTACT → permanent accounting loss on every future
  # fire. The `(<all numeric fields> | numbers)` type-check below rejects such a
  # slot, so it falls through to the FIRST-LEG path, which overwrites this
  # agent's slot with a clean baseline (self-heal — the same path fixture 145
  # exercises for an unparseable file). A VALID slot (every numeric field a
  # number) is still returned verbatim — no behavior change on the happy path.
  cond_bl_existing=""
  if [ -r "$BASELINE_FILE" ]; then
    cond_bl_existing=$(jq -c --arg aid "$agent_id" \
      'if (type == "object") and (has($aid)) and ((.[$aid] | type) == "object")
          and (.[$aid]
               | [.input, .cache_creation, .cache_read, .processed, .output, .turns]
               | map(numbers) | length == 6)
       then .[$aid] else empty end' \
      "$BASELINE_FILE" 2>/dev/null) || cond_bl_existing=""
  fi

  if [ -n "$cond_bl_existing" ]; then
    # LATER LEG — reuse the recorded baseline verbatim.
    cond_baseline_obj=$(printf '%s' "$cond_bl_existing" | jq -c \
      '{session_id: (.session_id // ""),
        input: (.input // 0), cache_creation: (.cache_creation // 0),
        cache_read: (.cache_read // 0), processed: (.processed // 0),
        output: (.output // 0), turns: (.turns // 0)}' 2>/dev/null) || cond_baseline_obj=""
    if [ -n "$cond_baseline_obj" ]; then
      cond_b_input=$(printf '%s' "$cond_baseline_obj" | jq -r '.input' 2>/dev/null)
      cond_b_cache_creation=$(printf '%s' "$cond_baseline_obj" | jq -r '.cache_creation' 2>/dev/null)
      cond_b_cache_read=$(printf '%s' "$cond_baseline_obj" | jq -r '.cache_read' 2>/dev/null)
      cond_b_output=$(printf '%s' "$cond_baseline_obj" | jq -r '.output' 2>/dev/null)
      cond_b_turns=$(printf '%s' "$cond_baseline_obj" | jq -r '.turns' 2>/dev/null)
      cond_baseline_is_legacy="false"
    fi
  else
    # FIRST LEG — record the baseline from the current cumulative, then use it.
    _cond_cand=$(_cond_bl_candidate)
    if _cond_bl_write_back "$_cond_cand"; then
      cond_baseline_obj="$_cond_cand"
      _cond_bl_adopt
      cond_baseline_is_legacy="false"
    fi
    # else: EC-3 — write failed → baseline = 0 this leg, no retry (legacy shape).
  fi

  # Compose the CONDUCTOR-TOKEN-EVENT via the shared lib (agent_id as session_id).
  if [ "$cond_baseline_is_legacy" = "true" ]; then
    event_line=$(compute_legacy_line "$usage_json" "$agent_id" "$now" "$final") || event_line=""
  else
    event_line=$(compute_delta_line "$usage_json" "$agent_id" "$now" "$final" \
      "$cond_b_input" "$cond_b_cache_creation" "$cond_b_cache_read" \
      "$cond_b_output" "$cond_b_turns" "$cond_baseline_obj") || event_line=""
  fi

  if [ -z "$event_line" ]; then
    echo "[subagent-stop] WARNING: failed to compose CONDUCTOR event JSON — skipping append" >&2
    exit 0
  fi

  # ── Step 9 (conductor): append CONDUCTOR-TOKEN-EVENT, exit 0 ────────────────
  # No self-refresh and no pointer rm (there is no pointer for a subagent
  # Conductor; the Conductor runs account-run.sh inside its own final turn — DQ 1/2).
  # OWNERSHIP-GATE: agent_id == delegate-state.json#conductor_agent_id (Step 8.0). Residual: inherits Step-6 agent_id-from-basename fallback (out of model).
  locked_append "$run_dir/log.md" "CONDUCTOR-TOKEN-EVENT: $event_line"
  exit 0
fi

# ── Step 4.7: Specialist ownership gate (idea #27 — nonce-in-transcript) ──────
# SPECIALIST PATH ONLY. The conductor branch proved ownership by its own means —
# the Step 8.0 conductor ownership gate (audit round 2): $agent_id must equal
# delegate-state.json#conductor_agent_id, or, on a pre-v2/legacy run with no
# delegate-state credential, it fails open — and then RETURNED above (`exit 0` at
# the end of the conductor block). So control only reaches here for a specialist
# SPAWN-TOKEN-EVENT. (The conductor branch does NOT use this specialist nonce gate:
# the Delegate's conductor spawn prompt carries no `Run nonce:` line and the run
# nonce is shared across specialists, so a nonce grep would false-reject the real
# Conductor — conductor_agent_id is the exact per-subagent credential instead.)
#
# The hole this closes: Steps 3+5 attribute a subagent purely because its first
# user message text contains "RUN_DIR: <this run>" + "Attempt ID: <role>-<n>".
# Any same-run subagent that echoed/quoted the spawn prompt (a nested helper, a
# re-spawn reusing the slug, a self-run analysis spawn that read log.md) is
# attributed — ownership-by-mention (class #22), still open for SPECIALIST tokens.
# This gate is the capture-time identity check conductor-stop.sh already has: it
# proves the subagent really carries THIS run's SECRET nonce, which lives ONLY in
# the run's pointer file and the transcripts of sessions genuinely spawned for the
# run (the Conductor puts it in the `Run nonce:` line of every specialist prompt —
# orchestrator.md). The nonce is NEVER in log.md, so a log-reader cannot forge it.
#
# Nonce source = the existing per-run nonce from the pointer (reuse, mirroring
# conductor-stop — NOT a fresh per-spawn nonce, which would need the registry the
# idea forbids). RESIDUAL: the run nonce is shared across a run's specialists, so
# it does NOT by itself distinguish specialist-A from specialist-B within one run;
# that residual is owned by account-tokens.sh's kept attempt_id->agent_id 1:1
# dedup (fixture 157, defense-in-depth), NOT by this gate. (docs/run-accounting.md)
#
# Pointer resolution reuses the #25 precedence EXACTLY as conductor-stop Step A.5:
#   1. BUREAU_POINTER_FILE set (non-empty) -> that one file (forced single-file).
#   2. Else -> directory mode: BUREAU_POINTER_DIR (default ~/.novadiem/active-runs)
#      keyed by the munged $run_dir (sed 's#[/.]#-#g', same munge orchestrator.md
#      /account-run.sh write with). subagent-stop.sh already knows the exact
#      $run_dir from the transcript, so it addresses the pointer DIRECTLY by key —
#      no directory enumeration and no ownership-select loop (simpler than
#      conductor-stop, which must DISCOVER which run it is).
#
# Three states, decided in this order (Q4):
#   1. Pointer resolves AND has a non-empty .nonce (normal, every live run):
#      the nonce MUST be present in the transcript. Present -> attribute.
#      ABSENT -> REJECT (do not append, exit 0). This is the closed gate.
#   2. Pointer does NOT resolve at all (file absent for $run_dir): legacy/archived
#      run, no pointer to verify against -> fail-OPEN, attribute by mention as
#      before, with a stderr note. SAFE: a foreign subagent cannot REMOVE the
#      pointer (only the run lifecycle writes/removes it), so it can never force
#      this carve-out on a live run; a live run always hits state 1.
#   3. Pointer resolves but .nonce is empty/malformed (corrupt pointer): fold into
#      state-2 fail-open (a pointer with no usable nonce is effectively no pointer)
#      so a corrupt pointer degrades to accept-by-mention, not silent data loss.
#
# The distinguisher for the carve-out is POINTER EXISTENCE, never "nonce absent
# from transcript" — keying the fallback on transcript content would reopen the
# hole (a foreigner would just omit the nonce and take the fallback).
_ptr_pointer_file=""
if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  # FORCED single-file mode — legacy path, same as conductor-stop.
  _ptr_pointer_file="$BUREAU_POINTER_FILE"
else
  _ptr_pointer_dir="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  _ptr_key=$(printf '%s' "$run_dir" | sed 's#[/.]#-#g')   # munge / and . -> -
  _ptr_pointer_file="$_ptr_pointer_dir/$_ptr_key"
fi

if [ -f "$_ptr_pointer_file" ]; then
  # Pointer exists → read its nonce.
  _ptr_nonce=$(jq -r '.nonce // empty' "$_ptr_pointer_file" 2>/dev/null) || _ptr_nonce=""
  if [ -n "$_ptr_nonce" ]; then
    # State 1 — the gate is CLOSED. The nonce MUST be in this subagent's own
    # transcript. -qF (fixed string), byte-identical to conductor-stop's grep.
    if grep -qF -- "$_ptr_nonce" "$transcript_path" 2>/dev/null; then
      : # OWNED — fall through to the SPECIALIST BRANCH and append as today.
    else
      # FOREIGN — the subagent read RUN_DIR (Step 3 matched) but never received
      # the nonce. Do NOT append. Hooks always exit 0.
      echo "[subagent-stop] specialist ownership gate: nonce for RUN_DIR $run_dir not found in subagent transcript — not attributing (foreign/duplicate subagent or un-migrated in-flight run)" >&2
      exit 0
    fi
  else
    # State 3 — pointer present but nonce empty/malformed → fold into fail-open.
    echo "[subagent-stop] specialist ownership gate: pointer for RUN_DIR $run_dir has no usable nonce — attributing by mention (corrupt-pointer fail-open)" >&2
  fi
else
  # State 2 — no pointer for this run (legacy/archived) → fail-open by mention.
  echo "[subagent-stop] specialist ownership gate: no pointer file for RUN_DIR $run_dir — attributing by mention (pointer-less legacy/archived run fail-open)" >&2
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SPECIALIST BRANCH (unchanged) — compose a SPAWN-TOKEN-EVENT line.
# ═══════════════════════════════════════════════════════════════════════════
event_line=""
if [ -n "$attempt_note" ]; then
  # attempt_id is null — include _note
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg agent_id "$agent_id" \
    --arg at "$now" \
    --arg note "$attempt_note" \
    '{
      attempt_id: null,
      _note: $note,
      agent_id: $agent_id,
      at: $at,
      turns: .turns,
      tokens: {
        input: .input,
        cache_creation: .cache_creation,
        cache_read: .cache_read,
        processed: .processed,
        output: .output
      }
    }' 2>/dev/null) || event_line=""
else
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg attempt_id "$attempt_id_raw" \
    --arg agent_id "$agent_id" \
    --arg at "$now" \
    '{
      attempt_id: $attempt_id,
      agent_id: $agent_id,
      at: $at,
      turns: .turns,
      tokens: {
        input: .input,
        cache_creation: .cache_creation,
        cache_read: .cache_read,
        processed: .processed,
        output: .output
      }
    }' 2>/dev/null) || event_line=""
fi

if [ -z "$event_line" ]; then
  echo "[subagent-stop] WARNING: failed to compose event JSON — skipping append" >&2
  exit 0
fi

# ── Step 9: Append to log.md ─────────────────────────────────────────────────
# OWNERSHIP-GATE: run nonce in transcript (Step 4.7)
locked_append "$run_dir/log.md" "SPAWN-TOKEN-EVENT: $event_line"

exit 0
