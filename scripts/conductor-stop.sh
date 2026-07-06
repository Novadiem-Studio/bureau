#!/usr/bin/env bash
# conductor-stop.sh — Claude Code Stop hook (Bundle 11, Phase 3).
#
# Fires once per main-session response and once after the session ends.
# Captures the Conductor's own token usage from the main transcript,
# manages the FR 6 pointer file lifecycle, and performs a one-shot
# final capture with self-refresh on the first post-closure fire.
#
# CRITICAL: This hook fires for EVERY Claude Code main session on this
# machine. Non-bureau sessions exit 0 silently via the fail-safe ladder.
# A crash or non-zero exit here would disrupt unrelated work — all
# own-errors log to stderr and exit 0.
#
# Fail-safe ladder (checked in order; first miss → exit 0 silently):
#   A   stop_hook_active guard — prevents hook re-entry loops
#   A.5 resolve pointer path (BUREAU_POINTER_FILE or default)
#   B   pointer file present and valid JSON with three required keys
#   C   both NONCE and RUN_DIR present in transcript file content
#   D   RUN_DIR exists as a directory AND RUN_DIR/log.md is readable
#
# Portability: Bash 3.2 + jq on macOS. No set -e (hooks must always
# exit 0); errors are logged to stderr. No associative arrays, no
# GNU-only date flags.
#
# Field names confirmed in docs/run-accounting.md § "Hook field names
# (Bundle 11 ground truth)": transcript_path, session_id, stop_hook_active.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Step A: Loop guard ───────────────────────────────────────────────────────
# If stop_hook_active is true the hook is already running for this session
# event. Exit 0 immediately to prevent a hook re-entry loop.
stdin_json=$(cat)
stop_hook_active=$(printf '%s' "$stdin_json" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

# ── Step A.5: Resolve pointer path ──────────────────────────────────────────
# Specified once here; used for ALL pointer reads, existence checks, and the
# compare-before-rm removal in Step G(3). Tests set BUREAU_POINTER_FILE to a
# path inside a temp dir so no fixture touches the real ~/.novadiem directory.
POINTER_FILE="${BUREAU_POINTER_FILE:-$HOME/.novadiem/bureau-active-run}"
ACCOUNT_RUN_SH="${BUREAU_ACCOUNT_RUN_SH:-$SCRIPT_DIR/account-run.sh}"

# ── Step B: Read and validate the pointer file ──────────────────────────────
# The pointer file is one-line JSON:
#   {"run_dir":"<abs path>","nonce":"<token>","written_at":"<ISO-8601>"}
if [ ! -e "$POINTER_FILE" ]; then
  exit 0  # No active bureau run — silent no-op
fi

pointer_json=$(cat "$POINTER_FILE" 2>/dev/null)
if [ -z "$pointer_json" ]; then
  echo "[conductor-stop] pointer file unreadable or empty: $POINTER_FILE" >&2
  exit 0
fi

RUN_DIR=$(printf '%s' "$pointer_json" | jq -r '.run_dir // empty' 2>/dev/null)
NONCE=$(printf '%s' "$pointer_json" | jq -r '.nonce // empty' 2>/dev/null)
written_at=$(printf '%s' "$pointer_json" | jq -r '.written_at // empty' 2>/dev/null)

if [ -z "$RUN_DIR" ] || [ -z "$NONCE" ] || [ -z "$written_at" ]; then
  echo "[conductor-stop] pointer file missing required keys (run_dir/nonce/written_at): $POINTER_FILE" >&2
  exit 0
fi

# ── Step C: Ownership check (content-grep on transcript file) ───────────────
# The transcript path is the confirmed field name from docs/run-accounting.md.
# The transcript file lives at a munged-cwd path like:
#   ~/.claude/projects/-Users-robin-Code-novadiem-bureau/<session-id>.jsonl
# This path NEVER contains RUN_DIR or NONCE — a path-based check would always
# fail and silently drop all conductor records. The check must grep FILE CONTENT.
#
# Check 1: nonce must be present in transcript content.
# Check 2: RUN_DIR must be present in transcript content.
# If EITHER fails → exit 0. This closes EC 14: an eval/inspection session
# whose transcript contains RUN_DIR but NOT the nonce exits 0 here.
transcript_path=$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$transcript_path" ] || [ ! -r "$transcript_path" ]; then
  exit 0  # No readable transcript — silent no-op
fi

if ! grep -qF -- "$NONCE" "$transcript_path" 2>/dev/null; then
  exit 0
fi
if ! grep -qF -- "$RUN_DIR" "$transcript_path" 2>/dev/null; then
  exit 0
fi

# ── Step D: Verify RUN_DIR is usable ────────────────────────────────────────
if [ ! -d "$RUN_DIR" ] || [ ! -r "$RUN_DIR/log.md" ]; then
  exit 0  # Run archived or cleaned up — silent no-op
fi

# ── Step E: Sum transcript usage and read closure evidence ───────────────────
# shellcheck source=lib/bureau-token-lib.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bureau-token-lib.sh"

usage_json=$(sum_transcript_usage "$transcript_path" 2>/dev/null) || usage_json=""
if [ -z "$usage_json" ]; then
  usage_json='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0,"turns":0}'
  echo "[conductor-stop] WARNING: sum_transcript_usage returned empty for $transcript_path — emitting zero-token event" >&2
fi

# Confirmed field name: session_id (docs/run-accounting.md ground truth)
session_id=$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""
if [ -z "$session_id" ]; then
  session_id="unknown"
fi

# Read closure evidence: parse state.json for accounting.status.
# Fail-safe: missing/unreadable/unparseable state.json → treat as OPEN (never
# false-positive on closure — a false-positive would trigger pointer removal
# before the run is actually closed).
final="false"
if [ -r "$RUN_DIR/state.json" ]; then
  accounting_status=$(jq -r '.accounting.status // empty' "$RUN_DIR/state.json" 2>/dev/null) || accounting_status=""
  # CLOSED when accounting.status is present AND not "pending"
  if [ -n "$accounting_status" ] && [ "$accounting_status" != "pending" ]; then
    final="true"
  fi
fi

# ── Step E.5: Resolve baseline (four-row state machine) ──────────────────────
# Placed AFTER Step E because the first-fire and EC-4 re-record branches need
# usage_json (the session cumulative from sum_transcript_usage) to compute the
# baseline value. No second sum_transcript_usage call — read the one in scope.
#
# jq distinguishes an ABSENT baseline key from an explicit null via has():
# plain `.baseline` is null for BOTH. Absent = pre-Bundle-16 pointer = legacy.
#
#   pointer .baseline          Action
#   ─────────────────────────  ──────────────────────────────────────────────
#   has("baseline")==false     Legacy — subtract 0, emit the old 6-key shape, no
#                              write (FR 6, FR 7, EC 1).
#   null                       First fire — record baseline = {session_id +
#                              current cumulative}, write back (two-step guard),
#                              then use it. Write fails → baseline=0 this fire,
#                              no retry (EC 3).
#   object, .session_id == sid Use it verbatim — same baseline every fire (FR 3).
#   object, .session_id != sid Resumed leg in a new session — re-record a fresh
#                              baseline for THIS session, write back, use it
#                              (EC 4). Write fails → baseline=0 this fire.
#
# Sets for Step F:
#   baseline_is_legacy  true|false  (true also covers the EC-3 write-fail fallback:
#                                    emit the old 6-key shape with no baseline key)
#   baseline_session_id, baseline_input, baseline_cache_creation,
#   baseline_cache_read, baseline_processed, baseline_output, baseline_turns
#                       integers (0 when legacy)
#   baseline_obj_json   the baseline object emitted on the line (empty when legacy)

# Default to the legacy (fail-open) shape; flipped to non-legacy only once a valid
# baseline object is resolved and — for the null / EC-4 rows — durably written.
baseline_is_legacy="true"
baseline_session_id=""
baseline_input=0
baseline_cache_creation=0
baseline_cache_read=0
baseline_processed=0
baseline_output=0
baseline_turns=0
baseline_obj_json=""

# Compose a candidate baseline object from the current session cumulative.
_bl_candidate() {
  printf '%s' "$usage_json" | jq -c --arg sid "$session_id" \
    '{session_id: $sid, input: .input, cache_creation: .cache_creation,
      cache_read: .cache_read, processed: .processed, output: .output, turns: .turns}' \
    2>/dev/null
}

# Adopt a just-recorded candidate as the in-memory baseline (deltas ≈ 0 this fire).
_bl_adopt_candidate() {
  baseline_session_id="$session_id"
  baseline_input=$(printf '%s' "$usage_json" | jq -r '.input // 0' 2>/dev/null)
  baseline_cache_creation=$(printf '%s' "$usage_json" | jq -r '.cache_creation // 0' 2>/dev/null)
  baseline_cache_read=$(printf '%s' "$usage_json" | jq -r '.cache_read // 0' 2>/dev/null)
  baseline_processed=$(printf '%s' "$usage_json" | jq -r '.processed // 0' 2>/dev/null)
  baseline_output=$(printf '%s' "$usage_json" | jq -r '.output // 0' 2>/dev/null)
  baseline_turns=$(printf '%s' "$usage_json" | jq -r '.turns // 0' 2>/dev/null)
}

# Two-step write-back guard (enrollment printf is not atomic — a sibling run
# can write a fresh pointer between our pre-mv check and the mv, or after the
# mv but before our re-read).
# Returns 0 only if the pointer still names THIS run's run_dir+nonce both before
# AND after the atomic mv. A lost race → return 1; caller degrades to
# baseline=0 this fire, no retry.
#
# Post-mv re-read scope: guards only the POST-mv window. If a sibling writes
# AFTER our mv but BEFORE our re-read, we see their pointer, bail (return 1),
# and correctly degrade — no wrong value emitted by either run.
#
# Pre-check→mv window: UNDETECTABLE. If a sibling enrolls in this window our
# mv overwrites their fresh pointer; the re-read then sees our own just-written
# content and passes tautologically. The sibling's capture is silently lost —
# it degrades to partial / baseline=0 (EC 5: honest degrade, no wrong value).
# This is a deliberately-unmitigated residual; a real fix needs CAS (O_EXCL /
# hardlink) or a mutex shared with the enrollment writer (see bureau-token-lib
# mkdir mutex). Collision window: milliseconds, first-fire only, never observed.
# $1 = candidate baseline object JSON.
_bl_write_back() {
  local cand="$1" pre_run pre_nonce post_run post_nonce tmp_ptr
  [ -n "$cand" ] || return 1
  # (1) Pre-mv check: does the pointer still name THIS run?
  [ -e "$POINTER_FILE" ] || return 1
  pre_run=$(jq -r '.run_dir // empty' "$POINTER_FILE" 2>/dev/null) || pre_run=""
  pre_nonce=$(jq -r '.nonce // empty' "$POINTER_FILE" 2>/dev/null) || pre_nonce=""
  [ "$pre_run" = "$RUN_DIR" ] && [ "$pre_nonce" = "$NONCE" ] || return 1
  # (2) Compose a fresh four-key pointer, preserving run_dir/nonce/written_at
  #     verbatim (only baseline is added), and publish via temp-file + atomic mv.
  #     The temp file lives beside the pointer so the mv is same-filesystem/atomic
  #     (mirrors scripts/account-run.sh's ".accounting.json.tmp.XXXXXX" pattern).
  tmp_ptr=$(mktemp "${POINTER_FILE}.tmp.XXXXXX" 2>/dev/null) || return 1
  if ! printf '%s' "$pointer_json" | jq -c --argjson baseline "$cand" \
        '{run_dir: .run_dir, nonce: .nonce, written_at: .written_at, baseline: $baseline}' \
        > "$tmp_ptr" 2>/dev/null; then
    rm -f "$tmp_ptr" 2>/dev/null
    return 1
  fi
  if ! mv "$tmp_ptr" "$POINTER_FILE" 2>/dev/null; then
    rm -f "$tmp_ptr" 2>/dev/null
    return 1
  fi
  # (3) Post-mv re-read: confirm the pointer still names THIS run (race not lost).
  post_run=$(jq -r '.run_dir // empty' "$POINTER_FILE" 2>/dev/null) || post_run=""
  post_nonce=$(jq -r '.nonce // empty' "$POINTER_FILE" 2>/dev/null) || post_nonce=""
  [ "$post_run" = "$RUN_DIR" ] && [ "$post_nonce" = "$NONCE" ] || return 1
  return 0
}

baseline_state=$(printf '%s' "$pointer_json" | jq -r \
  'if (has("baseline") | not) then "legacy"
   elif (.baseline == null) then "null"
   elif (.baseline | type) == "object" then "object"
   else "legacy" end' 2>/dev/null) || baseline_state="legacy"

case "$baseline_state" in
  legacy)
    : # keep legacy defaults — subtract 0, emit the old 6-key shape (FR 6/7)
    ;;
  null)
    # First fire for this run — record the baseline from the current cumulative.
    _bl_cand=$(_bl_candidate)
    if _bl_write_back "$_bl_cand"; then
      baseline_obj_json="$_bl_cand"
      _bl_adopt_candidate
      baseline_is_legacy="false"
    fi
    # else: EC 3 — write failed / race lost → baseline=0 this fire, no retry.
    ;;
  object)
    _bl_sid=$(printf '%s' "$pointer_json" | jq -r '.baseline.session_id // ""' 2>/dev/null) || _bl_sid=""
    if [ -n "$_bl_sid" ] && [ "$_bl_sid" = "$session_id" ]; then
      # Same session — reuse the recorded baseline verbatim (FR 3).
      _bl_obj=$(printf '%s' "$pointer_json" | jq -c \
        '.baseline | {session_id: (.session_id // ""),
                      input: (.input // 0), cache_creation: (.cache_creation // 0),
                      cache_read: (.cache_read // 0), processed: (.processed // 0),
                      output: (.output // 0), turns: (.turns // 0)}' 2>/dev/null) || _bl_obj=""
      if [ -n "$_bl_obj" ]; then
        baseline_obj_json="$_bl_obj"
        baseline_session_id="$_bl_sid"
        baseline_input=$(printf '%s' "$_bl_obj" | jq -r '.input' 2>/dev/null)
        baseline_cache_creation=$(printf '%s' "$_bl_obj" | jq -r '.cache_creation' 2>/dev/null)
        baseline_cache_read=$(printf '%s' "$_bl_obj" | jq -r '.cache_read' 2>/dev/null)
        baseline_processed=$(printf '%s' "$_bl_obj" | jq -r '.processed' 2>/dev/null)
        baseline_output=$(printf '%s' "$_bl_obj" | jq -r '.output' 2>/dev/null)
        baseline_turns=$(printf '%s' "$_bl_obj" | jq -r '.turns' 2>/dev/null)
        baseline_is_legacy="false"
      fi
    else
      # EC 4 — baseline tagged with a different (or missing) session_id: re-record
      # a fresh baseline for THIS session so the resumed leg is not clamped to ~0
      # by subtracting the prior session's (large) baseline.
      _bl_cand=$(_bl_candidate)
      if _bl_write_back "$_bl_cand"; then
        baseline_obj_json="$_bl_cand"
        _bl_adopt_candidate
        baseline_is_legacy="false"
      fi
      # else: EC 3 — write failed / race lost → baseline=0 this fire, no retry.
    fi
    ;;
esac

# ── Step F: Append CONDUCTOR-TOKEN-EVENT ─────────────────────────────────────
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$baseline_is_legacy" = "true" ]; then
  # Legacy branch (absent baseline key OR the EC-3 write-fail fallback): emit the
  # exact pre-Bundle-16 6-key shape — byte-for-byte identical to today's output on
  # the same input (FR 6, AC 6). No baseline key, no _note. Do NOT reorder keys.
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg session_id "$session_id" \
    --arg at "$now" \
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
    }' 2>/dev/null) || event_line=""
else
  # Non-legacy branch: subtract the baseline per field from the raw cumulative and
  # clamp each delta ≥ 0 (input/cache_creation/cache_read/output/turns). Re-derive
  # processed from the CLAMPED components (never clamp processed on its own) so the
  # processed == input+cache_creation+cache_read identity holds and AC 7's bound is
  # satisfied by construction (FR 2). Attach the baseline object (OQ 4, audit) and,
  # if any field clamped, a _note naming each clamped field with its raw/baseline
  # pair (FR 4 / EC 2). Key order: session_id, at, turns, tokens, final, baseline,
  # then _note last (only when a clamp fired).
  event_line=$(printf '%s' "$usage_json" | jq -c \
    --arg session_id "$session_id" \
    --arg at "$now" \
    --argjson final "$final" \
    --argjson b_input "$baseline_input" \
    --argjson b_cache_creation "$baseline_cache_creation" \
    --argjson b_cache_read "$baseline_cache_read" \
    --argjson b_output "$baseline_output" \
    --argjson b_turns "$baseline_turns" \
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
    ' 2>/dev/null) || event_line=""
fi

if [ -z "$event_line" ]; then
  echo "[conductor-stop] WARNING: failed to compose event JSON — skipping append" >&2
  exit 0
fi

locked_append "$RUN_DIR/log.md" "CONDUCTOR-TOKEN-EVENT: $event_line"

# If the run is still open, nothing more to do — pointer stays in place.
if [ "$final" = "false" ]; then
  exit 0
fi

# ── Step G: One-shot final capture (final=true ONLY) ─────────────────────────
# THE ORDER IS MANDATORY AND LOAD-BEARING. Do not reorder these three steps.
#
# (1) CONDUCTOR-TOKEN-EVENT with final:true was already appended in Step F.
#     Do not append again.
#
# (2) Best-effort self-refresh: re-run account-run.sh to rewrite accounting.json
#     to "exact" from the now-complete log.md.
#     Stdout is suppressed: the Claude Code harness JSON-parses exit-0 hook
#     stdout; any non-JSON text produces undefined harness behavior, so the
#     hook's stdout channel must stay clean. The call is best-effort — wrap
#     in a safe conditional and log failure to stderr only.
if "$ACCOUNT_RUN_SH" "$RUN_DIR" >/dev/null 2>/dev/null; then
  :
else
  echo "[conductor-stop] self-refresh via $ACCOUNT_RUN_SH failed — accounting.json stays partial" >&2
fi

# (3) Compare-before-rm: remove the pointer ONLY if it still names this run's
#     run_dir AND nonce. Re-read to detect the case where a newer run has
#     already enrolled (overwritten the pointer with its own nonce/path).
if [ ! -e "$POINTER_FILE" ]; then
  exit 0  # Already removed — nothing to do
fi
current_run_dir=$(jq -r '.run_dir // empty' "$POINTER_FILE" 2>/dev/null) || current_run_dir=""
current_nonce=$(jq -r '.nonce // empty' "$POINTER_FILE" 2>/dev/null) || current_nonce=""
if [ "$current_run_dir" = "$RUN_DIR" ] && [ "$current_nonce" = "$NONCE" ]; then
  rm "$POINTER_FILE" 2>/dev/null || true
fi
# If either differs, leave the pointer untouched — a newer run has enrolled.

exit 0
