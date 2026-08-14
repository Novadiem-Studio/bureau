#!/usr/bin/env bash
# Aggregate one run's accounting signals into <RUN_DIR>/accounting.json.
#
# Usage:
#   ./scripts/account-run.sh <RUN_DIR>
#
# Reads (all under RUN_DIR unless noted):
#   state.json            — required; hard-fail if wholly absent
#   log.md                — optional; absent = empty specialist_spawns[] + _note
#   model-routing.json    — optional; fallback to model-tiers.json; else unavailable
#   ~/.novadiem/usage-snapshot.json (or $NOVADIEM_USAGE_SNAPSHOT_PATH) — optional
#
# Emits:
#   <RUN_DIR>/accounting.json — conforms to templates/accounting.json; idempotent (overwrite)
#
# Exit codes:
#   0  successful emit (including every degrade-and-emit path)
#   1  bad arguments, missing RUN_DIR, or missing state.json
#
# Bash 3.2 / macOS portable: no associative arrays; two-pass event reduction via jq + temp files.

set -euo pipefail

# Resolve this script's own directory so sibling scripts (account-tokens.sh) can be
# invoked by path without hardcoding the install location (Bundle 11, Step A2).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 10 min — canonical staleness rule, scripts/README.md: stale if polledAt older than
# ~10 min or ok=false. This is the ONLY staleness threshold in this script.
readonly USAGE_SNAPSHOT_MAX_AGE_SECONDS=600

die() { echo "[account-run] ERROR: $*" >&2; exit 1; }

# Join the remaining args with a literal "; " (semicolon + single space) — the ONE note
# separator used everywhere in _specialist_spawns_note. Not `IFS='; '` + ${arr[*]}: that
# join honors only the FIRST IFS char, so it would emit ";" with no space and disagree with
# the "; " segments built by the ${x:+$x; } pattern in Step 6. Bash 3.2 safe; no args → "".
join_note_sep() {
    local sep="; " out="" part first=1
    for part in "$@"; do
        if [ "$first" -eq 1 ]; then out="$part"; first=0; else out="$out$sep$part"; fi
    done
    printf '%s' "$out"
}

# ── 1. argument handling ──────────────────────────────────────────────────────

[ $# -eq 1 ] || die "Usage: account-run.sh <RUN_DIR> — exactly one argument required"
RUN_DIR="$1"
case "$RUN_DIR" in
  /*) ;;
  *)  die "RUN_DIR must be an absolute path, got: $RUN_DIR" ;;
esac
[ -d "$RUN_DIR" ] || die "RUN_DIR does not exist or is not a directory: $RUN_DIR"

command -v jq >/dev/null 2>&1 || die "jq is required but not found on PATH"

# ── 2. state.json — HARD FAIL if wholly absent, DEGRADE if thin/corrupt ───────

STATE_JSON="$RUN_DIR/state.json"
[ -f "$STATE_JSON" ] || die "state.json not found in RUN_DIR — not a valid framework run dir: $RUN_DIR"

# F4 (B6): validate-once, early. A present-but-corrupt state.json (unparseable OR a
# valid-JSON non-object — e.g. a JSON array, or a half-written interrupted run) is the
# abnormal case terminal accounting exists to CAPTURE: degrade every state-derived
# field to unavailable and STILL emit accounting.json (schema_version 1) with a
# top-level _state_note. The ONLY hard-fail stays "wholly absent" (line 61 above) —
# that is "not a framework run dir", a caller error, not an abnormal run. `jq -e
# 'type=="object"'` (rc-based, 2>/dev/null) fails on BOTH corrupt shapes; it mirrors
# the B8 usage-snapshot validate-once precedent. Every downstream state.json read is
# already `2>/dev/null`-guarded and takes its unavailable else-branch when corrupt, so
# the only remaining unguarded read (the Step 8 memory_type at ~589) is guarded below.
if jq -e 'type == "object"' "$STATE_JSON" >/dev/null 2>&1; then
    STATE_CORRUPT="false"
else
    STATE_CORRUPT="true"
fi

slug=$(basename "$RUN_DIR")

# Per-field presence+type guards. A present-but-thin state.json (interrupted run) degrades
# absent/wrong-type fields to {value:null, confidence:"unavailable"} with a _note.

# workflow — must be a non-empty string
if jq -e 'has("workflow") and ((.workflow | type) == "string") and ((.workflow | length) > 0)' \
    "$STATE_JSON" >/dev/null 2>&1; then
    workflow=$(jq -r '.workflow' "$STATE_JSON")
    workflow_conf="exact"
    workflow_note=""
else
    workflow="null"   # bound via --argjson in Step 9
    workflow_conf="unavailable"
    workflow_note="workflow absent or not a non-empty string in state.json"
fi

# phases_complete — must be an array
if jq -e 'has("phases_complete") and ((.phases_complete | type) == "array")' \
    "$STATE_JSON" >/dev/null 2>&1; then
    phases_complete=$(jq -c '.phases_complete' "$STATE_JSON")
    phases_conf="exact"
    phases_note=""
else
    phases_complete="null"   # bound via --argjson in Step 9
    phases_conf="unavailable"
    phases_note="phases_complete absent or not an array in state.json"
fi

# phase_status — must be a string
if jq -e 'has("phase_status") and ((.phase_status | type) == "string")' \
    "$STATE_JSON" >/dev/null 2>&1; then
    phase_status=$(jq -r '.phase_status' "$STATE_JSON")
    phase_status_conf="exact"
    phase_status_note=""
else
    phase_status="null"   # bound via --argjson in Step 9
    phase_status_conf="unavailable"
    phase_status_note="phase_status absent or not a string in state.json"
fi

# critic_loops — must be an object
if jq -e 'has("critic_loops") and ((.critic_loops | type) == "object")' \
    "$STATE_JSON" >/dev/null 2>&1; then
    critic_loops=$(jq -c '.critic_loops' "$STATE_JSON")
    critic_loops_conf="exact"
    critic_loops_note=""
else
    critic_loops="null"   # bound via --argjson in Step 9
    critic_loops_conf="unavailable"
    critic_loops_note="critic_loops absent or not an object in state.json"
fi

# ── 3. run_date — two-stage validation of the slug prefix ─────────────────────

slug_prefix=$(echo "$slug" | cut -c1-8)

# Stage 1 — format: must match ^[0-9]{8}$
if ! echo "$slug_prefix" | grep -qE '^[0-9]{8}$'; then
    run_date_val=null
    run_date_conf="unavailable"
else
    # Stage 2 — calendar reality
    yyyy="${slug_prefix:0:4}"
    mm="${slug_prefix:4:2}"
    dd="${slug_prefix:6:2}"
    # Force base-10 (leading zeros would otherwise be read as octal)
    yr=$((10#$yyyy))
    mo=$((10#$mm))
    dy=$((10#$dd))

    calendar_valid=false
    if [ "$yr" -ge 1 ] && [ "$yr" -le 9999 ] && [ "$mo" -ge 1 ] && [ "$mo" -le 12 ]; then
        max_days=31
        case $mo in
          1|3|5|7|8|10|12) max_days=31 ;;
          4|6|9|11)        max_days=30 ;;
          2)
            # Leap year: divisible by 4, except century years not divisible by 400
            if (( yr % 400 == 0 )); then
                max_days=29
            elif (( yr % 100 == 0 )); then
                max_days=28
            elif (( yr % 4 == 0 )); then
                max_days=29
            else
                max_days=28
            fi
            ;;
        esac
        if [ "$dy" -ge 1 ] && [ "$dy" -le "$max_days" ]; then
            calendar_valid=true
        fi
    fi

    if $calendar_valid; then
        run_date_val="\"$slug_prefix\""
        run_date_conf="exact"
    else
        run_date_val=null
        run_date_conf="unavailable"
    fi
fi
# NB: run_date never falls back to state.json#last_updated or RUN_DIR mtime.

# ── 5. usage snapshot ─────────────────────────────────────────────────────────

SNAPSHOT_PATH="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"

# Initialize note variables early so they are always bound (set -u) even on the
# non-malformed path. Every unavailable field with a note variable must bind it into
# jq AND include it conditionally in the emitted leaf (Step 9).
polled_at_note=""
age_seconds_note=""
stale_note=""
quota_gauge_note=""

if [ ! -f "$SNAPSHOT_PATH" ]; then
    # Absent — not an error; emit unavailable fields.
    snapshot_present_val=false
    polled_at_val=null; polled_at_conf="unavailable"
    polled_at_note="usage snapshot absent — ~/.novadiem/usage-snapshot.json not found"
    age_seconds_val=null; age_seconds_conf="unavailable"
    age_seconds_note="usage snapshot absent — ~/.novadiem/usage-snapshot.json not found"
    # stale is {null, unavailable} when NO snapshot exists — NOT {false, exact}.
    # You cannot observe staleness of a snapshot that is not there.
    snapshot_stale=null; stale_conf="unavailable"
    stale_note="usage snapshot absent — ~/.novadiem/usage-snapshot.json not found"
    quota_gauge_conf="unavailable"; quota_gauge_val=null
    quota_gauge_note="usage snapshot absent — ~/.novadiem/usage-snapshot.json not found"
else
    snapshot_json=$(cat "$SNAPSHOT_PATH")

    # File EXISTS but may not be a usable snapshot. Validate ONCE up front that it
    # parses AND is a JSON OBJECT — the .ok/.polledAt reads below index it with string
    # keys, so a non-object value (number/string/array/bool/null) would throw "Cannot
    # index <type> with string". Under `set -euo pipefail` that abort would strand any
    # prior accounting.json (exit 5). `jq -e 'type == "object"'` fails (non-zero) on
    # BOTH an unparseable file AND any valid-JSON non-object — NOT `jq -e .`, whose
    # exit status keys off output TRUTHINESS, so 42/[]/""/0/true would pass it and fall
    # through to the unguarded reads. A present-but-unusable file degrades the ENTIRE
    # usage_snapshot block to unavailable and continues to a normal atomic emit
    # (exit 0) — operationally identical to the absent case, distinguished by note.
    if ! printf '%s' "$snapshot_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        # present:false — consistent with the absent-case precedent. The field gates
        # "is there a USABLE snapshot"; a corrupt file is no usable snapshot, same as
        # absent. present:true would mislead a consumer into expecting readable fields.
        snapshot_present_val=false
        corrupt_note="usage snapshot file present but not a usable JSON object — could not parse or not an object; treated as no usable data"
        polled_at_val=null; polled_at_conf="unavailable"
        polled_at_note="$corrupt_note"
        age_seconds_val=null; age_seconds_conf="unavailable"
        age_seconds_note="$corrupt_note"
        # stale is null (not false): you cannot observe staleness of unparseable data.
        snapshot_stale=null; stale_conf="unavailable"
        stale_note="$corrupt_note"
        quota_gauge_conf="unavailable"; quota_gauge_val=null
        quota_gauge_note="$corrupt_note"
    else
    snapshot_present_val=true
    snapshot_ok=$(printf '%s' "$snapshot_json" | jq -r '.ok // false')
    polled_at_str=$(printf '%s' "$snapshot_json" | jq -r '.polledAt // empty')

    # Compute age with jq fromdateiso8601 — portable across macOS BSD date and GNU date,
    # whose -d / -j flags diverge. Guard it: a malformed/absent polledAt errors.
    if ! age_seconds=$(printf '%s' "$snapshot_json" | \
        jq -r 'now - (.polledAt | fromdateiso8601) | floor' 2>/dev/null); then
        # polledAt missing or malformed — degrade, do not abort.
        age_seconds_val=null
        age_seconds_conf="unavailable"
        age_seconds_note="polledAt missing or not parseable as ISO-8601"
        polled_at_val=null; polled_at_conf="unavailable"
        polled_at_note="polledAt missing or not parseable as ISO-8601"
        snapshot_stale=true  # treat as stale — boolean string for --argjson
        stale_conf="exact"
        quota_gauge_conf="unavailable"; quota_gauge_val=null
    else
        age_seconds_val="$age_seconds"
        age_seconds_conf="exact"
        polled_at_val="\"$polled_at_str\""
        polled_at_conf="exact"

        # Stale when age > max OR ok != true. if/then assigns the boolean string.
        if [ "$age_seconds" -gt "$USAGE_SNAPSHOT_MAX_AGE_SECONDS" ] || \
           [ "$snapshot_ok" != "true" ]; then
            snapshot_stale=true
        else
            snapshot_stale=false
        fi
        stale_conf="exact"

        # quota_gauge: estimated if fresh+ok, unavailable if stale/ok:false.
        if [ "$snapshot_stale" = "false" ]; then
            quota_gauge_conf="estimated"
            # Percent fields are nested under .claude — NOT top-level.
            quota_gauge_val=$(printf '%s' "$snapshot_json" | \
                jq '{sessionUsedPercent: .claude.sessionUsedPercent,
                     weeklyUsedPercent: .claude.weeklyUsedPercent,
                     sonnetUsedPercent: .claude.sonnetUsedPercent}')
        else
            quota_gauge_conf="unavailable"; quota_gauge_val=null
        fi
    fi
    fi   # close: present-but-valid-JSON branch (the corrupt-file guard's else)
fi

# ── 5.5 configured_model resolver (defined before any call site) ──────────────

ROUTING_FILE="$RUN_DIR/model-routing.json"
TIERS_FILE="$RUN_DIR/model-tiers.json"

get_configured_model() {
    local role="$1"
    if [ -f "$ROUTING_FILE" ]; then
        local model
        # Each role entry is an OBJECT with fields role/model/agent/tier/... — use
        # .roles[$role].model for the model-name string (the object itself is not it).
        model=$(jq -r --arg role "$role" '.roles[$role].model // empty' "$ROUTING_FILE" 2>/dev/null)
        if [ -n "$model" ]; then
            echo "exact:$model"; return
        fi
    fi
    if [ -f "$TIERS_FILE" ]; then
        local tier
        # resolved-model-tiers.json shape: {roles: {analyst: {tier: "sonnet", ...}}}.
        # The tier name maps 1:1 to the model name in this framework.
        tier=$(jq -r --arg role "$role" '.roles[$role].tier // empty' "$TIERS_FILE" 2>/dev/null)
        if [ -n "$tier" ]; then
            echo "inferred:$tier"; return
        fi
    fi
    echo "unavailable:null"
}

# ── 5.6 persona↔cast-key alias map (Bug 3 — attempt_id role-prefix drift) ──────
# The cast keys used in model-routing.json (challenger/cleric/spellwright/…) and the
# persona-file stems (critic/designer/prompt-engineer/…) name the SAME role. A
# Conductor that keys attempt_id off one scheme while writing `role` in the other
# (observed: role:"critic" with attempt_id:"challenger-1", role:"designer" with
# "cleric-1") produced a canon-CORRECT role field but a prefix the strict gate below
# rejected — silently dropping a spawn whose role was valid. This helper returns the
# accepted attempt_id prefixes for a role: the role itself PLUS its persona/cast
# alias (either direction). A genuinely-mismatched attempt_id (e.g. "architect-1" on
# role:"critic") maps to neither and still fails — the check stays meaningful.
# The role field is kept as-is (canon), and attempt_id stays VERBATIM as the sole
# pairing key (never rewritten), so pairing with the hook's SPAWN-TOKEN-EVENT and the
# started/terminal collapse are unaffected.
role_alias() {
    case "$1" in
        critic)          echo "challenger" ;;
        challenger)      echo "critic" ;;
        designer)        echo "cleric" ;;
        cleric)          echo "designer" ;;
        prompt-engineer) echo "spellwright" ;;
        spellwright)     echo "prompt-engineer" ;;
        backend)         echo "systemsmith" ;;
        systemsmith)     echo "backend" ;;
        frontend)        echo "mage" ;;
        mage)            echo "frontend" ;;
        sysadmin)        echo "mechanic" ;;
        mechanic)        echo "sysadmin" ;;
        voice)           echo "counselor" ;;
        counselor)       echo "voice" ;;
        *)               echo "" ;;   # analyst/architect/etc. share one name — no alias
    esac
}

# ── 6. SPAWN-EVENT parse → specialist_spawns[] ────────────────────────────────

# STEP 6.0 — temp files for the two-pass reduction (Bash 3.2 has no associative
# arrays). tmp_out empty so the trap can reference it before Step 9 assigns it.
started_tmp=$(mktemp "${TMPDIR:-/tmp}/account-run.started.XXXXXX")
terminal_tmp=$(mktemp "${TMPDIR:-/tmp}/account-run.terminal.XXXXXX")
tmp_out=""
# tmp_prefix mirrors tmp_out's mktemp path but is NEVER blanked after the publish
# (tmp_out is set to "" post-mv so the trap won't rm the now-final accounting.json).
# The EXIT trap uses tmp_prefix to sweep any intermediate dotfile a mid-pipeline jq
# failure leaked into RUN_DIR — ${tmp_prefix}.mem (§ 9) and
# ${tmp_prefix}.{tok,enrich,v2,warn,tnote} (§ 9.5). Each of those steps is an
# `<jq> > "${tmp_out}.X" && mv …` list whose jq failure is exempt from set -e, so the
# script continues to publish and would otherwise strand the partial dotfile. Guarded
# on a non-empty prefix in cleanup so an empty value never degrades the glob to ".*"
# against the CWD.
tmp_prefix=""
cleanup() {
    rm -f "$started_tmp" "$terminal_tmp"
    if [ -n "$tmp_out" ]; then
        rm -f "$tmp_out"
    fi
    if [ -n "$tmp_prefix" ]; then
        rm -f "${tmp_prefix}."*
    fi
    return 0
}
trap cleanup EXIT

# STEP 6.1 — guard log.md FIRST, then grep (never grep a missing file).
_specialist_spawns_note=""
spawn_parse_errors=()
spawn_event_line_count=0

# Always bound before the guard (set -u safety for the absent-log branch).
pass2_result='{"spawns":[],"orphan_notes":"","dup_notes":""}'
specialist_spawns_json='[]'

if [ ! -r "$RUN_DIR/log.md" ]; then
    _specialist_spawns_note="log.md absent or unreadable — no SPAWN-EVENT: lines available"
else
    while IFS= read -r raw_line; do
        spawn_event_line_count=$((spawn_event_line_count + 1))
        lineno="${raw_line%%:*}"           # source line number from grep -n
        rest="${raw_line#*:}"              # strip the "lineno:" grep -n prefix
        payload="${rest#SPAWN-EVENT: }"    # strip the SPAWN-EVENT: prefix → JSON or key=value

        # STEP 6.1b — key=value fallback. The canonical payload is compact JSON, but Conductors
        # in practice also emit space-separated `key=value` pairs (observed on multiple real runs;
        # see docs/evaluation/framework-evaluation-log.md 2026-07-01). If the payload is not a JSON
        # object (doesn't start with `{`), convert `k=v k=v …` to JSON: `attempt` becomes a JSON
        # number, every other value a JSON string. Values are simple tokens (no spaces/quotes)
        # because the pairs are space-delimited, so no escaping is needed.
        case "$payload" in
            '{'*) : ;;   # already JSON — leave as-is
            *=*)
                payload=$(printf '%s' "$payload" | awk '{
                    printf "{"; first=1;
                    for (i=1;i<=NF;i++){
                        eq=index($i,"=");
                        if(eq==0) continue;
                        k=substr($i,1,eq-1); v=substr($i,eq+1);
                        if(!first) printf ","; first=0;
                        if(k=="attempt") printf "\"%s\":%s", k, v;
                        else printf "\"%s\":\"%s\"", k, v;
                    }
                    printf "}";
                }')
                ;;
        esac

        # STEP 6.2 — strict one-value parse gate. -cs slurps into an array; length==1 → .[0],
        # else error(). Rejects empty/whitespace-only (len 0) and two-values-on-one-line (len 2+).
        # NOT -e (which would misclassify valid null/false/0/""/[] as parse failures).
        if ! parsed=$(printf '%s' "$payload" | \
            jq -cs 'if length == 1 then .[0] else error("expected exactly one JSON value") end' \
            2>/dev/null); then
            spawn_parse_errors+=("line $lineno: jq parse failure or not exactly one JSON value")
            continue
        fi

        # STEP 6.2b — object-type check.
        event_type=$(printf '%s' "$parsed" | jq -r 'type')
        if [ "$event_type" != "object" ]; then
            spawn_parse_errors+=("line $lineno: event is not a JSON object (was: $event_type)")
            continue
        fi

        # STEP 6.3 — validate all seven required keys (presence AND JSON type) with per-key
        # diagnostics. has() is explicit: a missing key reads as "null" under jq -r, identical
        # to a JSON null value, so presence must be checked separately.
        validation_result=$(printf '%s' "$parsed" | jq -r '
            if (has("role") | not) then "missing key: role"
            elif ((.role | type) != "string") then "wrong type for role: expected string, got \(.role | type)"
            elif ((.role | length) == 0) then "role is empty string"
            elif (has("agent") | not) then "missing key: agent"
            elif ((.agent | type) != "string") then "wrong type for agent: expected string, got \(.agent | type)"
            elif ((.agent | length) == 0) then "agent is empty string"
            elif (has("configured_model") | not) then "missing key: configured_model"
            elif ((.configured_model | type) != "string") then "wrong type for configured_model: expected string, got \(.configured_model | type)"
            elif ((.configured_model | length) == 0) then "configured_model is empty string"
            elif (has("actual_model") | not) then "missing key: actual_model"
            elif (has("attempt") | not) then "missing key: attempt"
            elif ((.attempt | type) != "number") then "wrong type for attempt: expected number/integer, got \(.attempt | type)"
            elif (.attempt != (.attempt | floor)) then "attempt must be a JSON integer (no fractional part), got \(.attempt)"
            elif (.attempt < 1) then "attempt must be >= 1, got \(.attempt)"
            elif (has("attempt_id") | not) then "missing key: attempt_id"
            elif ((.attempt_id | type) != "string") then "wrong type for attempt_id: expected string, got \(.attempt_id | type)"
            elif ((.attempt_id | length) == 0) then "attempt_id is empty string"
            elif (has("status") | not) then "missing key: status"
            elif ((.status | type) != "string") then "wrong type for status: expected string, got \(.status | type)"
            else "valid"
            end
        ' 2>/dev/null || echo "jq validation predicate failed")
        if [ "$validation_result" != "valid" ]; then
            spawn_parse_errors+=("line $lineno: $validation_result")
            continue
        fi

        # All seven keys confirmed present with correct JSON types — extract safely.
        role=$(printf '%s' "$parsed" | jq -r '.role')
        agent=$(printf '%s' "$parsed" | jq -r '.agent')
        attempt_raw=$(printf '%s' "$parsed" | jq -r '.attempt')   # confirmed integer >= 1
        attempt_id=$(printf '%s' "$parsed" | jq -r '.attempt_id')
        status=$(printf '%s' "$parsed" | jq -r '.status')

        # actual_model: key confirmed present; distinguish null vs string type.
        actual_model_type=$(printf '%s' "$parsed" | jq -r '.actual_model | type')
        if [ "$actual_model_type" = "null" ]; then
            actual_model_conf="unavailable"
        elif [ "$actual_model_type" = "string" ]; then
            actual_model_conf="exact"
        else
            spawn_parse_errors+=("line $lineno: actual_model must be string or null, got: $actual_model_type")
            continue
        fi

        # attempt_id must be role-prefixed (role + "-" + <suffix>). Relaxed from strict equality
        # with "${role}-${attempt}" so descriptive per-pass suffixes (e.g. challenger-r1-1,
        # cleric-brief-1) are accepted while the role linkage is preserved. Bug 3: also accept a
        # persona/cast ALIAS prefix of the role (role:"critic" + attempt_id:"challenger-1", etc.)
        # so a spawn whose `role` field is canon-correct is not dropped merely because the
        # attempt_id prefix uses the sibling naming scheme. attempt_id itself is kept VERBATIM as
        # the pairing key (never rewritten). A genuine role/attempt_id mismatch (e.g.
        # "architect-1" on role:"critic") matches neither prefix and still fails. Uniqueness
        # across spawns is enforced downstream by keying started/terminal pairs on attempt_id.
        role_alt=$(role_alias "$role")
        case "$attempt_id" in
            "${role}-"?*) : ;;
            *)
                if [ -n "$role_alt" ]; then
                    case "$attempt_id" in
                        "${role_alt}-"?*) : ;;
                        *)
                            spawn_parse_errors+=("line $lineno: attempt_id '$attempt_id' not prefixed by role '${role}-' or its alias '${role_alt}-'")
                            continue
                            ;;
                    esac
                else
                    spawn_parse_errors+=("line $lineno: attempt_id '$attempt_id' not prefixed by role '${role}-'")
                    continue
                fi
                ;;
        esac

        # status legal values.
        case "$status" in
          started|complete|no-handoff|failed|terminated) ;;
          *) spawn_parse_errors+=("line $lineno: illegal status value: $status"); continue ;;
        esac

        # The Conductor is not a specialist spawn; direct mode is top-level, and
        # Delegate v2 captures it on the Conductor token rail instead.
        if [ "$role" = "conductor" ]; then
            _specialist_spawns_note="${_specialist_spawns_note:+$_specialist_spawns_note; }line $lineno: conductor SPAWN-EVENT excluded (the Conductor is never a specialist spawn)"
            continue
        fi

        # STEP 6.4 — write events to temp files via jq (safe escaping; actual_model kept
        # as its native JSON type for downstream {value} emission).
        if [ "$status" = "started" ]; then
            # Duplicate-started check via jq exact equality (grep is unsafe — attempt_id may
            # contain BRE metacharacters). Slurp started_tmp, count attempt_id matches.
            dup_count=$(jq -s --arg id "$attempt_id" \
                '[.[] | select(.attempt_id == $id)] | length' \
                "$started_tmp" 2>/dev/null || echo 0)
            if [ "$dup_count" -gt 0 ]; then
                _specialist_spawns_note="${_specialist_spawns_note:+$_specialist_spawns_note; }line $lineno: duplicate status:started for attempt_id $attempt_id — keeping first"
                continue
            fi
            printf '%s' "$parsed" | jq -c \
                --arg am_conf "$actual_model_conf" \
                '{attempt_id, role, agent, attempt,
                  actual_model_val: .actual_model,
                  actual_model_conf: $am_conf,
                  reported_status: "started"}' >> "$started_tmp"
        else
            printf '%s' "$parsed" | jq -c \
                --argjson lineno "$lineno" \
                '{attempt_id, status, lineno: $lineno}' >> "$terminal_tmp"
        fi

    done < <(grep -n '^SPAWN-EVENT:' "$RUN_DIR/log.md")

    # True zero-event case is detected via the line counter, NOT started_tmp emptiness
    # (started_tmp can be empty when all lines were terminal-only or malformed — those
    # are already described by parse errors / orphan notes).
    if [ "$spawn_event_line_count" -eq 0 ]; then
        _specialist_spawns_note="${_specialist_spawns_note:+$_specialist_spawns_note; }no structured SPAWN-EVENT: lines found in log.md — run may predate the SPAWN-EVENT convention or log was not written"
    fi

    # STEP 6.5 — Pass 2: apply terminals in source order against the started map via jq.
    # Order is explicit and deterministic: each started event carries _order (its 0-based
    # appearance index in started-event/log order). The map is only a pairing index for
    # applying terminals by attempt_id; the emitted spawns array is sorted by _order, so the
    # result never depends on jq's object-key insertion order surviving the from_entries round-trip.
    pass2_result=$(jq -s '
        (.[0] // []) as $started |
        (.[1] // []) as $terminals |
        ($started
         | to_entries
         | map(.value + {_order: .key})
         | map({key: .attempt_id, value: .})
         | from_entries) as $map |
        reduce $terminals[] as $t (
            {map: $map, orphan_notes: [], dup_notes: []};
            if .map[$t.attempt_id] == null then
                .orphan_notes += ["line \($t.lineno): orphan terminal for \($t.attempt_id) — no started event, skipped"]
            elif .map[$t.attempt_id].reported_status != "started" then
                .dup_notes += ["line \($t.lineno): duplicate terminal for \($t.attempt_id) (\($t.status)) — first terminal kept"]
            else
                .map[$t.attempt_id].reported_status = $t.status
            end
        ) |
        {spawns: (.map | to_entries | map(.value) | sort_by(._order) | map(del(._order))),
         orphan_notes: (.orphan_notes | join("; ")),
         dup_notes: (.dup_notes | join("; "))}
    ' \
        <(if [ -s "$started_tmp" ]; then jq -s '.' "$started_tmp"; else echo '[]'; fi) \
        <(if [ -s "$terminal_tmp" ]; then jq -s '.' "$terminal_tmp"; else echo '[]'; fi) \
    2>/dev/null || echo '{"spawns":[],"orphan_notes":"","dup_notes":""}')

    # Accumulate orphan/dup notes.
    orphan_notes=$(printf '%s' "$pass2_result" | jq -r '.orphan_notes // ""')
    dup_notes=$(printf '%s' "$pass2_result" | jq -r '.dup_notes // ""')
    for note in "$orphan_notes" "$dup_notes"; do
        [ -n "$note" ] && \
            _specialist_spawns_note="${_specialist_spawns_note:+$_specialist_spawns_note; }$note"
    done
fi

# STEP 6.6 — post-process each entry: resolve configured_model and assemble {value,confidence}.
specialist_spawns_json=$(printf '%s' "$pass2_result" | jq -r '.spawns[] | @json' | \
    while IFS= read -r entry_json; do
        entry_role=$(printf '%s' "$entry_json" | jq -r '.role')
        entry_agent=$(printf '%s' "$entry_json" | jq -r '.agent')
        entry_attempt=$(printf '%s' "$entry_json" | jq -r '.attempt')
        # attempt_id is NOT emitted — internal pairing/dedup key only.
        entry_attempt_id=$(printf '%s' "$entry_json" | jq -r '.attempt_id // empty')
        entry_reported_status=$(printf '%s' "$entry_json" | jq -r '.reported_status')
        entry_am_conf=$(printf '%s' "$entry_json" | jq -r '.actual_model_conf')
        # actual_model_val: raw JSON value (may be null or string) — use jq for safe access.
        entry_am_val=$(printf '%s' "$entry_json" | jq -c '.actual_model_val')

        cfg_result=$(get_configured_model "$entry_role")
        cfg_conf="${cfg_result%%:*}"
        cfg_val_raw="${cfg_result#*:}"

        # unavailable path binds JSON null (the string "null" would violate the contract).
        if [ "$cfg_conf" = "unavailable" ]; then
            jq_cfg_args=( --argjson cfg_val "null" )
            cfg_note="configured_model unavailable — no model-routing.json or model-tiers.json found in RUN_DIR"
        else
            jq_cfg_args=( --arg cfg_val "$cfg_val_raw" )
            cfg_note=""
        fi

        # FR 12: model-vs-routing divergence detection.
        # Ground truth: the re-resolved configured_model from model-routing.json (cfg_val_raw),
        # NOT the logged configured_model field on the SPAWN-EVENT (which is Conductor-authored).
        # actual_model: from the SPAWN-EVENT's actual_model_val.
        entry_actual_model=$(printf '%s' "$entry_json" | jq -r '.actual_model_val // empty')
        divergence_note=""
        if [ -n "$entry_actual_model" ] && [ "$entry_actual_model" != "null" ] \
           && [ "$cfg_conf" != "unavailable" ] \
           && [ "$entry_actual_model" != "$cfg_val_raw" ]; then
            # Candidate divergence — check for a matching MODEL-OVERRIDE: line in log.md.
            # Grep with PATH pinned (EC 10 ugrep guard):
            PATH=/usr/bin:$PATH
            override_match=$(grep "^MODEL-OVERRIDE:" "$RUN_DIR/log.md" 2>/dev/null \
              | jq -Rrs --arg aid "$entry_attempt_id" --arg cfg "$cfg_val_raw" --arg act "$entry_actual_model" '
                  [split("\n")[] | select(startswith("MODEL-OVERRIDE:")) |
                   ltrimstr("MODEL-OVERRIDE: ") | try fromjson catch null |
                   select(type == "object" and .attempt_id == $aid
                          and .configured == $cfg and .actual == $act)] | length > 0
                ')
            if [ "$override_match" != "true" ]; then
                # Bug 4 — POST-HOC RECONCILE (docs/run-accounting.md § 6). No actor ever
                # hand-writes MODEL-OVERRIDE on a genuine quota downgrade, so an actual!=
                # configured divergence read as a permanent protocol violation forever. The
                # honest SPAWN-EVENT already carries the true `actual_model` (the Conductor
                # picked the downgrade and logged it), so the divergence IS self-declared.
                # Auto-emit a MODEL-OVERRIDE: line for it here — the ONE seam that holds BOTH
                # halves at once (configured re-resolved from model-routing.json, actual from
                # the event) — with a shell-computed `at` (the one unfakeable clock; never a
                # typed timestamp), then drop the violation. The auto-emitted line matches the
                # $override_match grep above, so a second account-run.sh invocation finds it
                # present and neither re-emits (idempotent) nor re-flags.
                override_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                override_line=$(jq -cn \
                    --arg role "$entry_role" \
                    --arg aid  "$entry_attempt_id" \
                    --arg cfg  "$cfg_val_raw" \
                    --arg act  "$entry_actual_model" \
                    --arg at   "$override_at" \
                    '{role:$role,attempt_id:$aid,configured:$cfg,actual:$act,
                      reason:"auto-reconciled from SPAWN-EVENT actual_model; no hand-written override",
                      at:$at}')
                printf 'MODEL-OVERRIDE: %s\n' "$override_line" >> "$RUN_DIR/log.md"
                # Divergence is now self-declared, not a violation — leave divergence_note empty.
            fi
        fi

        # One {value,confidence}-formatted specialist_spawns entry. attempt_id NOT emitted.
        printf '%s' "$entry_json" | jq -c \
            --arg role "$entry_role" \
            --arg agent "$entry_agent" \
            --argjson attempt "$entry_attempt" \
            --arg cfg_conf "$cfg_conf" \
            --arg cfg_note "$cfg_note" \
            "${jq_cfg_args[@]}" \
            --argjson am_val "$entry_am_val" \
            --arg am_conf "$entry_am_conf" \
            --arg status "$entry_reported_status" \
            --arg divergence_note "$divergence_note" \
            '{role: {value: $role, confidence: "exact"},
              agent: {value: $agent, confidence: "exact"},
              attempt: {value: $attempt, confidence: "exact"},
              configured_model: ({value: $cfg_val, confidence: $cfg_conf}
                                 + if ($cfg_conf == "unavailable" and ($cfg_note | length) > 0)
                                   then {"_note": $cfg_note} else {} end),
              actual_model: {value: $am_val, confidence: $am_conf},
              reported_status: {value: $status, confidence: "exact"}}
             + (if ($divergence_note | length) > 0 then {_note: $divergence_note} else {} end)'
    done | jq -s '.' 2>/dev/null || echo '[]')

# FR 12: top-level divergence flag when any specialist spawn had a divergence note.
model_divergence_top=""
if printf '%s' "$specialist_spawns_json" | jq -e 'any(.[]; has("_note") and (._note | test("model divergence")))' >/dev/null 2>&1; then
    model_divergence_top="one or more specialist spawns had a configured/actual model divergence without a logged MODEL-OVERRIDE: line"
fi

# Parallel attempt_id array, index-aligned with specialist_spawns_json above: both
# iterate pass2_result.spawns[] in the same sorted (_order) sequence, so entry i in
# each corresponds to the same spawn. This carries the attempt_id § 6 ACTUALLY PARSED
# — verbatim, including descriptive ids like challenger-r1-1 — through to the STEP A2
# enrichment join, WITHOUT emitting attempt_id as a specialist_spawns[] leaf (that
# contract stands). The A2 enricher pairs on this key (the same one the hooks emit and
# account-tokens.sh keys spawn_tokens by), not a reconstructed role+"-"+attempt
# composite, which would miss any descriptive id and silently drop enrichment (W1).
spawn_attempt_ids_json=$(printf '%s' "$pass2_result" | jq -c '[.spawns[].attempt_id]' 2>/dev/null || echo '[]')

# ── 8. memory block — four scenarios; state.json#memory is the single switch ──

# F4 (B6): this was the ONE unguarded jq on $STATE_JSON. On a corrupt state.json it
# aborted the whole script under `set -e` (exit 5, no accounting.json) — the reproduced
# F4. Guard it: when STATE_CORRUPT, skip the read entirely and take the new "corrupt"
# case arm (all-unavailable, like the non-object arm). The `2>/dev/null || memory_type=
# "corrupt"` also catches a file that passed the early object-check but raced to
# corruption between reads (defensive).
if [ "$STATE_CORRUPT" = "true" ]; then
    memory_type="corrupt"
else
    memory_type=$(jq -r 'if has("memory") then (.memory | type) else "absent" end' "$STATE_JSON" 2>/dev/null) || memory_type="corrupt"
fi

case "$memory_type" in
  "absent")
      # Scenario 1: no memory key → omit block entirely.
      memory_json=""
      ;;
  "object")
      memory_count=$(jq '.memory | length' "$STATE_JSON")
      if [ "$memory_count" -eq 0 ]; then
          # Scenario 2: empty object → all six fields {null, unavailable}.
          memory_json=$(jq -n '{
              retrieval_count:        {value:null, confidence:"unavailable"},
              writes_proposed:        {value:null, confidence:"unavailable"},
              writes_accepted:        {value:null, confidence:"unavailable"},
              conflicts_flagged:      {value:null, confidence:"unavailable"},
              digest_freshness:       {value:null, confidence:"unavailable"},
              memory_preflight_passed:{value:null, confidence:"unavailable"}
          }')
      else
          # Scenario 4: non-empty object — validate each sub-field independently.
          memory_json=$(jq '{
              retrieval_count: (
                  if (.memory.retrieval_count | type) == "number" and
                     (.memory.retrieval_count | floor) == .memory.retrieval_count and
                     .memory.retrieval_count >= 0
                  then {value: .memory.retrieval_count, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "retrieval_count: missing or wrong type"}
                  end
              ),
              writes_proposed: (
                  if (.memory.writes_proposed | type) == "number" and
                     (.memory.writes_proposed | floor) == .memory.writes_proposed and
                     .memory.writes_proposed >= 0
                  then {value: .memory.writes_proposed, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "writes_proposed: missing or wrong type"}
                  end
              ),
              writes_accepted: (
                  if (.memory.writes_accepted | type) == "number" and
                     (.memory.writes_accepted | floor) == .memory.writes_accepted and
                     .memory.writes_accepted >= 0
                  then {value: .memory.writes_accepted, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "writes_accepted: missing or wrong type"}
                  end
              ),
              conflicts_flagged: (
                  if (.memory.conflicts_flagged | type) == "number" and
                     (.memory.conflicts_flagged | floor) == .memory.conflicts_flagged and
                     .memory.conflicts_flagged >= 0
                  then {value: .memory.conflicts_flagged, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "conflicts_flagged: missing or wrong type"}
                  end
              ),
              digest_freshness: (
                  if (.memory.digest_freshness | type) == "string"
                  then {value: .memory.digest_freshness, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "digest_freshness: missing or wrong type"}
                  end
              ),
              memory_preflight_passed: (
                  if (.memory.memory_preflight_passed | type) == "boolean"
                  then {value: .memory.memory_preflight_passed, confidence: "exact"}
                  else {value: null, confidence: "unavailable",
                        "_note": "memory_preflight_passed: missing or wrong type"}
                  end
              )
          }' "$STATE_JSON")
      fi
      ;;
  "corrupt")
      # F4 (B6): state.json itself is present but not a parseable JSON object — the
      # memory fields cannot be extracted. Same all-unavailable block as the non-object
      # arm, with a note naming the corrupt state.json (distinct from "memory is not an
      # object", which is a valid state.json with a bad .memory).
      memory_json=$(jq -n '{
          retrieval_count:         {value:null, confidence:"unavailable"},
          writes_proposed:         {value:null, confidence:"unavailable"},
          writes_accepted:         {value:null, confidence:"unavailable"},
          conflicts_flagged:       {value:null, confidence:"unavailable"},
          digest_freshness:        {value:null, confidence:"unavailable"},
          memory_preflight_passed: {value:null, confidence:"unavailable"},
          "_note": "state.json is present but not a parseable JSON object — memory fields cannot be extracted"
      }')
      ;;
  *)
      # Scenario 3: non-object (string/number/bool/array/null) → all six unavailable + _note.
      memory_json=$(jq -n '{
          retrieval_count:         {value:null, confidence:"unavailable"},
          writes_proposed:         {value:null, confidence:"unavailable"},
          writes_accepted:         {value:null, confidence:"unavailable"},
          conflicts_flagged:       {value:null, confidence:"unavailable"},
          digest_freshness:        {value:null, confidence:"unavailable"},
          memory_preflight_passed: {value:null, confidence:"unavailable"},
          "_note": "state.json#memory is present but not an object — cannot extract fields"
      }')
      ;;
esac

# ── 9. assemble and write atomically ──────────────────────────────────────────

accounted_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Temp file INSIDE RUN_DIR so mv is always an atomic same-filesystem rename
# (mktemp in $TMPDIR can be a different filesystem on macOS APFS).
tmp_out=$(mktemp "$RUN_DIR/.accounting.json.tmp.XXXXXX")
tmp_prefix="$tmp_out"   # persistent dotfile-sweep anchor for the EXIT trap (see § 6.0)

# Assemble the _specialist_spawns_note from parse errors + accumulated loop notes.
# All joins use join_note_sep → a uniform "; " separator, so an exact-string fixture matches.
spawns_note_parts=()
if [ "${#spawn_parse_errors[@]}" -gt 0 ]; then
    spawns_note_parts+=("parse errors: $(join_note_sep "${spawn_parse_errors[@]}")")
fi
[ -n "$_specialist_spawns_note" ] && \
    spawns_note_parts+=("$_specialist_spawns_note")
# Guard the [@] expansion: under `set -u` on Bash 3.2, ${arr[@]} on an EMPTY array throws
# "unbound variable". A clean run (no parse errors, no loop notes) leaves the array empty.
if [ "${#spawns_note_parts[@]}" -gt 0 ]; then
    final_spawns_note=$(join_note_sep "${spawns_note_parts[@]}")
else
    final_spawns_note=""
fi

# String fields that may be null when unavailable: --arg builds a valid JSON string,
# --argjson null binds JSON null (hand-building "\"$value\"" is unsafe with quotes/backslashes).
if [ "$workflow_conf" = "exact" ]; then
    workflow_jq_args=( --arg workflow_val "$workflow" )
else
    workflow_jq_args=( --argjson workflow_val "null" )
fi

if [ "$phase_status_conf" = "exact" ]; then
    phase_status_jq_args=( --arg phase_status_val "$phase_status" )
else
    phase_status_jq_args=( --argjson phase_status_val "null" )
fi

jq -n \
  --arg slug "$slug" \
  "${workflow_jq_args[@]}" \
  --arg workflow_conf "$workflow_conf" \
  --arg workflow_note "$workflow_note" \
  --arg run_date_conf "$run_date_conf" \
  --argjson run_date_val "$run_date_val" \
  --arg accounted_at "$accounted_at" \
  "${phase_status_jq_args[@]}" \
  --arg phase_status_conf "$phase_status_conf" \
  --arg phase_status_note "$phase_status_note" \
  --argjson phases_complete "$phases_complete" \
  --arg phases_conf "$phases_conf" \
  --arg phases_note "$phases_note" \
  --argjson critic_loops "$critic_loops" \
  --arg critic_loops_conf "$critic_loops_conf" \
  --arg critic_loops_note "$critic_loops_note" \
  --argjson snapshot_present "$snapshot_present_val" \
  --arg polled_at_conf "$polled_at_conf" \
  --argjson polled_at_val "$polled_at_val" \
  --arg polled_at_note "$polled_at_note" \
  --arg age_seconds_conf "$age_seconds_conf" \
  --argjson age_seconds_val "$age_seconds_val" \
  --arg age_seconds_note "$age_seconds_note" \
  --argjson snapshot_stale "$snapshot_stale" \
  --arg stale_conf "$stale_conf" \
  --arg stale_note "$stale_note" \
  --arg quota_gauge_conf "$quota_gauge_conf" \
  --arg quota_gauge_note "$quota_gauge_note" \
  --argjson quota_gauge_val "$quota_gauge_val" \
  --argjson spawns "$specialist_spawns_json" \
  --arg spawns_note "$final_spawns_note" \
  --arg model_divergence_top "$model_divergence_top" \
  '{ schema_version: 1,
     run: {
       slug:           {value: $slug, confidence: "exact"},
       workflow:       ({value: $workflow_val, confidence: $workflow_conf}
                        + if ($workflow_conf == "unavailable" and ($workflow_note | length) > 0)
                          then {"_note": $workflow_note} else {} end),
       run_date:       ({value: $run_date_val, confidence: $run_date_conf}
                        + if $run_date_conf == "unavailable"
                          then {"_note": "RUN_DIR basename does not begin with a valid YYYYMMDD calendar date — run_date cannot be determined"}
                          else {} end),
       started_at:     {value: null, confidence: "unavailable",
                        "_note": "no start-time source in scope for v1"},
       accounted_at:   {value: $accounted_at, confidence: "exact"}
     },
     specialist_spawns: $spawns,
     phases: {
       complete:     ({value: $phases_complete, confidence: $phases_conf}
                      + if ($phases_conf == "unavailable" and ($phases_note | length) > 0)
                        then {"_note": $phases_note} else {} end),
       status:       ({value: $phase_status_val, confidence: $phase_status_conf}
                      + if ($phase_status_conf == "unavailable" and ($phase_status_note | length) > 0)
                        then {"_note": $phase_status_note} else {} end),
       critic_loops: ({value: $critic_loops, confidence: $critic_loops_conf}
                      + if ($critic_loops_conf == "unavailable" and ($critic_loops_note | length) > 0)
                        then {"_note": $critic_loops_note} else {} end)
     },
     cost: {
       currency_estimate: {value: null, confidence: "unavailable",
                           "_note": "no token/cost source in scope for v1"},
       quota_gauge:       ({value: $quota_gauge_val, confidence: $quota_gauge_conf}
                           + if ($quota_gauge_conf == "unavailable" and ($quota_gauge_note | length) > 0)
                             then {"_note": $quota_gauge_note} else {} end)
     },
     usage_snapshot: {
       present:     {value: $snapshot_present, confidence: "exact"},
       polled_at:   ({value: $polled_at_val, confidence: $polled_at_conf}
                     + if ($polled_at_conf == "unavailable" and ($polled_at_note | length) > 0)
                       then {"_note": $polled_at_note} else {} end),
       age_seconds: ({value: $age_seconds_val, confidence: $age_seconds_conf}
                     + if ($age_seconds_conf == "unavailable" and ($age_seconds_note | length) > 0)
                       then {"_note": $age_seconds_note} else {} end),
       stale:       ({value: $snapshot_stale, confidence: $stale_conf}
                     + if ($stale_conf == "unavailable" and ($stale_note | length) > 0)
                       then {"_note": $stale_note} else {} end)
     }
   }
   + (if ($spawns_note | length) > 0 then {"_specialist_spawns_note": $spawns_note} else {} end)
   + (if ($model_divergence_top | length) > 0 then {"_model_divergence_note": $model_divergence_top} else {} end)
  ' > "$tmp_out"

# Conditionally add the memory block when present.
if [ -n "$memory_json" ]; then
    jq --argjson mem "$memory_json" '. + {memory: $mem}' "$tmp_out" > "${tmp_out}.mem" \
        && mv "${tmp_out}.mem" "$tmp_out"
fi

# F4 (B6): when state.json is corrupt, add a top-level _state_note breadcrumb so a
# reader sees WHY every state-derived field is unavailable (conditional merge, like
# _close_out_warning). schema_version stays 1 (the base assembly wrote it), all the
# per-field guards took their unavailable else-branches, and the run still emitted an
# artifact — the whole point of the degrade.
if [ "$STATE_CORRUPT" = "true" ]; then
    jq '. + {"_state_note": "state.json present but not a parseable JSON object — accounting degraded to schema_version 1, all state-derived fields unavailable"}' \
        "$tmp_out" > "${tmp_out}.snote" \
        && mv "${tmp_out}.snote" "$tmp_out"
fi

# ── 9.5 Bundle 11 — enforcement gate + token-metrics merge ────────────────────
# EVERY step below operates on $tmp_out via an intermediate temp file + atomic mv,
# so it stays inside the § 9 tmp pipeline. Nothing is ever written in-place to the
# final accounting.json; the single publish is the `mv "$tmp_out" ...` below. This
# preserves the FR 8 write invariant (last-writer-wins on concurrent invocations,
# never a torn file).

# STEP A1 — zero-SPAWN-EVENT enforcement gate (FR 11 / AC 6). Fires when the run
# shows evidence of spawns (a non-empty phases_complete OR narrative "Spawned"
# headings in log.md) yet log.md carries zero structured SPAWN-EVENT: lines — the
# signature of a close-out that never emitted machine-readable spawn records.
# grep -c already prints "0" and exits 1 on no-match, so `|| true` (NOT `|| echo 0`,
# which would concatenate to the un-parseable "0\n0") keeps the count a clean
# integer under set -e.
gate_spawn_event_count=0
[ -r "$RUN_DIR/log.md" ] && gate_spawn_event_count=$(grep -c '^SPAWN-EVENT:' "$RUN_DIR/log.md") || true

gate_spawned_heading_count=0
[ -r "$RUN_DIR/log.md" ] && gate_spawned_heading_count=$(grep -cE '^## .*Spawned' "$RUN_DIR/log.md") || true

# phases_complete non-empty: $phases_complete is compact JSON when exact, the literal
# string "null" when unavailable — guard on the confidence before asking jq for its
# length (jq length on null errors).
gate_phases_nonempty=false
if [ "$phases_conf" = "exact" ] && \
   [ "$(printf '%s' "$phases_complete" | jq 'length')" -gt 0 ]; then
    gate_phases_nonempty=true
fi

if [ "$gate_spawn_event_count" -eq 0 ] && \
   { [ "$gate_phases_nonempty" = true ] || [ "$gate_spawned_heading_count" -gt 0 ]; }; then
    echo "[CLOSE-OUT WARNING] log.md contains spawn headings or phases_complete is non-empty, but zero SPAWN-EVENT: lines found — accounting reflects no specialist spawns. Check that the Conductor emitted SPAWN-EVENT lines for all spawns."
    # Durable marker in accounting.json (AC 6). String "true" — matches the AC's
    # "or 'true' as string equivalent — whatever jq produces".
    jq '. + {"_close_out_warning": "true"}' "$tmp_out" > "${tmp_out}.warn" \
        && mv "${tmp_out}.warn" "$tmp_out"
fi

# STEP A1-FALLBACK — recover the WORK-SHAPE of unmatched SPAWN-TOKEN-EVENT specialists.
# The hook (subagent-stop.sh) emits SPAWN-TOKEN-EVENT: for every specialist even when the
# Conductor never emitted the paired SPAWN-EVENT: work-shape line. For each SPAWN-TOKEN-EVENT
# attempt_id with NO matching SPAWN-EVENT started line, synthesize one INFERRED
# specialist_spawns[] entry (role/agent/attempt from the token event; models unavailable;
# status complete/inferred) so the run's shape is not lost. Everything is confidence
# "inferred"/"unavailable" and carries an _note — a degraded recovery path, never a
# substitute for the emit.
#
# Runs UNCONDITIONALLY (not only in the zero-SPAWN-EVENT gate above): the same defect shape
# happens PARTIALLY too — a run that emitted SPAWN-EVENT for some specialists but not others
# would otherwise strand the token-only ones. The matched_aids_json exclusion guarantees no
# double-count against real SPAWN-EVENTs, so this is safe for the partial case. The
# [CLOSE-OUT WARNING] gate above is unchanged — it still fires only when zero SPAWN-EVENT
# lines exist; this block only changes when the INFERENCE runs, not when the warning fires.
#
# What is and is NOT recovered: these inferred entries recover the WORK-SHAPE (role/agent/
# attempt) and the run's AGGREGATE token total (summed separately in account-tokens.sh's
# processed_total). They do NOT recover PER-SPAWN token attribution: account-tokens.sh keys
# its spawn_tokens map on SPAWN-EVENT *started* records, so a token-only attempt_id has no
# spawn_tokens entry and STEP A2's by-index enrichment attaches nothing to it. Per-spawn
# tokens are recoverable only for specialists that DID get a SPAWN-EVENT (the partial case).
# Role is inferred from the attempt_id prefix (segment before the first "-", e.g.
# challenger-r1-1 -> challenger).
if [ -r "$RUN_DIR/log.md" ]; then
    # attempt_ids that DO have a SPAWN-EVENT started line (to exclude — no double-count).
    # PATH pinned (EC 10 ugrep guard). grep no-match exits 1; `{ grep || true; }` neutralizes
    # it INSIDE the pipe so `set -o pipefail` doesn't fail the whole substitution.
    PATH=/usr/bin:$PATH
    matched_aids_json=$({ grep '^SPAWN-EVENT:' "$RUN_DIR/log.md" 2>/dev/null || true; } \
        | sed 's/^SPAWN-EVENT: //' \
        | jq -Rrs '[split("\n")[] | select(length > 0) | (try fromjson catch null)
                   | select(type == "object" and .status == "started" and (.attempt_id | type) == "string")
                   | .attempt_id]' 2>/dev/null || echo '[]')
    [ -n "$matched_aids_json" ] || matched_aids_json='[]'

    # Build inferred specialist_spawns[] entries from unmatched SPAWN-TOKEN-EVENT lines,
    # deduped by attempt_id (first occurrence wins), sorted by first appearance.
    inferred_result=$({ grep '^SPAWN-TOKEN-EVENT:' "$RUN_DIR/log.md" 2>/dev/null || true; } \
        | sed 's/^SPAWN-TOKEN-EVENT: //' \
        | jq -Rrs --argjson matched "$matched_aids_json" '
            [ split("\n")[] | select(length > 0) | (try fromjson catch null)
              | select(type == "object" and (.attempt_id | type) == "string" and (.attempt_id | length) > 0) ]
            # dedup by attempt_id, keep first appearance order
            | reduce .[] as $e ({seen: {}, ord: []};
                if (.seen[$e.attempt_id] == null)
                then {seen: (.seen + {($e.attempt_id): true}), ord: (.ord + [$e])}
                else . end)
            | .ord
            # drop any attempt_id already covered by a SPAWN-EVENT started line (no double-count)
            | map(select((.attempt_id as $a | $matched | index($a)) == null))
            | { aids: [ .[].attempt_id ],
                spawns: [ .[]
                  | (.attempt_id | split("-")[0]) as $role
                  # trailing numeric segment of the attempt_id → attempt number, else 1
                  | (.attempt_id | (capture("-(?<n>[0-9]+)$") // {n: "1"}) | .n | tonumber) as $attempt
                  | (.agent_id // "inferred") as $agent
                  | { role:             {value: $role, confidence: "inferred"},
                      agent:            {value: $agent, confidence: "inferred"},
                      attempt:          {value: $attempt, confidence: "inferred"},
                      configured_model: {value: null, confidence: "unavailable"},
                      actual_model:     {value: null, confidence: "unavailable"},
                      reported_status:  {value: "complete", confidence: "inferred"},
                      _note: "inferred from SPAWN-TOKEN-EVENT — no SPAWN-EVENT pair; Conductor may not have emitted the work-shape line" }
                ] }
          ' 2>/dev/null || echo '{"aids":[],"spawns":[]}')
    [ -n "$inferred_result" ] || inferred_result='{"aids":[],"spawns":[]}'

    inferred_count=$(printf '%s' "$inferred_result" | jq '.spawns | length' 2>/dev/null || echo 0)
    if [ "$inferred_count" -gt 0 ]; then
        # Append inferred spawns to specialist_spawns[] in tmp_out (after any real
        # SPAWN-EVENT-derived entries; the partial case keeps those exact entries first).
        jq --argjson inf "$(printf '%s' "$inferred_result" | jq '.spawns')" \
           '.specialist_spawns = ((.specialist_spawns // []) + $inf)' \
           "$tmp_out" > "${tmp_out}.fallback" && mv "${tmp_out}.fallback" "$tmp_out"

        # Keep spawn_attempt_ids_json index-aligned with specialist_spawns[] so STEP A2's
        # by-index enrichment can still pair the REAL (SPAWN-EVENT-backed) entries to their
        # tokens. The inferred entries have no spawn_tokens map entry (keyed on SPAWN-EVENT
        # started records), so A2 attaches nothing to them — but the alignment must not drift
        # for the exact entries that precede them, hence the append here mirrors the append above.
        spawn_attempt_ids_json=$(printf '%s' "$inferred_result" \
            | jq -c --argjson base "$spawn_attempt_ids_json" '$base + .aids' 2>/dev/null \
            || printf '%s' "$spawn_attempt_ids_json")

        # Name the inferred attempt_ids in _specialist_spawns_note.
        inferred_aids_csv=$(printf '%s' "$inferred_result" | jq -r '.aids | join(", ")' 2>/dev/null || echo "")
        fallback_note="inferred ${inferred_count} specialist spawn(s) from SPAWN-TOKEN-EVENT lines with no matching SPAWN-EVENT (attempt_ids: ${inferred_aids_csv}) — Conductor did not emit the work-shape line"
        jq --arg n "$fallback_note" '
            . + {"_specialist_spawns_note":
                 (if has("_specialist_spawns_note")
                  then (._specialist_spawns_note + "; " + $n) else $n end)}' \
            "$tmp_out" > "${tmp_out}.fbnote" && mv "${tmp_out}.fbnote" "$tmp_out"
    fi
fi

# STEP A2 — invoke the post-hoc aggregator, then account-tokens.sh, and merge their
# stdout contracts (FR 8 channel pin). The aggregator is the sole per-leg token
# source when it returns its valid, non-gated contract; otherwise per-leg figures
# remain unavailable. Neither consumer writes into RUN_DIR.
AGGREGATE_SCRIPT="$SCRIPT_DIR/aggregate-transcripts.sh"
posthoc_frag=""
posthoc_usable=0
posthoc_merged=0
posthoc_reuse_bound=false
posthoc_prior_bound=""
posthoc_prior_basis=""
posthoc_prior_accounted_at="null"

# W4 steps 1-2: read the prior close-out anchor before this invocation publishes
# anything, then fingerprint only records close-out itself never appends.
if [ -r "$RUN_DIR/accounting.json" ] && \
   jq -e 'type == "object"' "$RUN_DIR/accounting.json" >/dev/null 2>&1; then
    posthoc_prior_bound=$(jq -r 'if (._posthoc.run_ended_at | type) == "string" then ._posthoc.run_ended_at else empty end' \
        "$RUN_DIR/accounting.json" 2>/dev/null || echo "")
    posthoc_prior_basis=$(jq -c '._posthoc.basis // empty' \
        "$RUN_DIR/accounting.json" 2>/dev/null || echo "")
    posthoc_prior_accounted_at=$(jq -c '.run.accounted_at // null' \
        "$RUN_DIR/accounting.json" 2>/dev/null || echo "null")
    [ -n "$posthoc_prior_accounted_at" ] || posthoc_prior_accounted_at="null"
fi

posthoc_spawn_events=0
if [ -r "$RUN_DIR/log.md" ]; then
    # Exact, line-anchored prefix including its separating space; PATH-pinned so
    # a user-installed grep cannot reinterpret the accounting basis.
    posthoc_spawn_events=$(PATH=/usr/bin:$PATH grep -c '^SPAWN-EVENT: ' \
        "$RUN_DIR/log.md" 2>/dev/null || true)
    [ -n "$posthoc_spawn_events" ] || posthoc_spawn_events=0
fi

posthoc_conductor_legs=0
if [ -r "$RUN_DIR/delegate-state.json" ]; then
    posthoc_conductor_legs=$(jq -r '
      [ ((if (.conductor_agent_ids | type) == "array"
            then .conductor_agent_ids[] else empty end)),
        (if (.conductor_agent_id | type) == "string"
         then .conductor_agent_id else empty end) ]
      | map(select(type == "string" and length > 0)) | unique | length
    ' "$RUN_DIR/delegate-state.json" 2>/dev/null || echo 0)
    [ -n "$posthoc_conductor_legs" ] || posthoc_conductor_legs=0
fi

posthoc_basis=$(jq -cn --argjson spawn_events "$posthoc_spawn_events" \
    --argjson conductor_legs "$posthoc_conductor_legs" \
    '{spawn_events:$spawn_events,conductor_legs:$conductor_legs}')

if [ -n "$posthoc_prior_bound" ] && [ -n "$posthoc_prior_basis" ] && \
   jq -en --argjson prior "$posthoc_prior_basis" --argjson current "$posthoc_basis" \
      '$prior == $current' >/dev/null 2>&1; then
    posthoc_bound="$posthoc_prior_bound"
    posthoc_reuse_bound=true
else
    posthoc_bound=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# The fragment is consumed twice (derived metrics, then the sole per-leg write).
# Its mktemp prefix is under tmp_prefix, so the existing EXIT sweep removes it
# on every early exit and after the final publish.
if [ -x "$AGGREGATE_SCRIPT" ]; then
    posthoc_frag=$(mktemp "${tmp_out}.posthoc.XXXXXX")
    if "$AGGREGATE_SCRIPT" "$RUN_DIR" --until "$posthoc_bound" \
         > "$posthoc_frag" 2>/dev/null && \
       jq -e 'type == "object"
              and (has("_runtime_gap") | not)
              and ((.delegate | type) == "object")
              and ((.delegate.tokens | type) == "object")
              and ((.conductor | type) == "object")
              and ((.conductor.tokens | type) == "object")
              and ((.specialists | type) == "array")
              and all(.specialists[]; (.tokens | type) == "object")' \
          "$posthoc_frag" >/dev/null 2>&1; then
        posthoc_usable=1
    fi
fi

# Runtime agent ids are not public specialist_spawns leaves. Build the narrow
# attempt→agent comparison map from the still-present hook records; ambiguous
# multi-agent live claims become null and therefore cannot trigger a guessed
# mismatch disposition.
posthoc_live_agents='{}'
if [ "$posthoc_usable" -eq 1 ] && [ -r "$RUN_DIR/log.md" ]; then
    posthoc_live_agents=$({ PATH=/usr/bin:$PATH grep '^SPAWN-TOKEN-EVENT: ' \
          "$RUN_DIR/log.md" 2>/dev/null || true; } \
      | sed 's/^SPAWN-TOKEN-EVENT: //' \
      | jq -Rsc '
          [split("\n")[] | select(length > 0) | (try fromjson catch null)
           | select(type == "object"
                    and (.attempt_id | type) == "string"
                    and (.agent_id | type) == "string")]
          | group_by(.attempt_id)
          | map((.[0].attempt_id) as $aid
                | ([.[].agent_id] | unique) as $agents
                | {key:$aid,value:(if ($agents | length) == 1 then $agents[0] else null end)})
          | from_entries
        ' 2>/dev/null || echo '{}')
    [ -n "$posthoc_live_agents" ] || posthoc_live_agents='{}'
fi

TOKENS_SCRIPT="$SCRIPT_DIR/account-tokens.sh"
if [ -x "$TOKENS_SCRIPT" ]; then
    # Capture stdout only. Guard the command substitution under set -e: a non-zero
    # exit from account-tokens.sh must NOT abort account-run.sh — a token-consumer
    # failure degrades to today's schema, it never strands the accounting write.
    if [ "$posthoc_usable" -eq 1 ]; then
        tokens_json=$("$TOKENS_SCRIPT" "$RUN_DIR" "$posthoc_frag" 2>/dev/null) && tokens_invoke_ok=1 || tokens_invoke_ok=0
    elif tokens_json=$("$TOKENS_SCRIPT" "$RUN_DIR" 2>/dev/null); then
        tokens_invoke_ok=1
    else
        tokens_invoke_ok=0
    fi

    if [ "$tokens_invoke_ok" -eq 1 ] && \
       printf '%s' "$tokens_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        # Valid JSON object. Decide whether it actually carries Bundle 11 data. An
        # "all-empty fragment" (no CONDUCTOR/SPAWN-TOKEN/CHECKPOINT events, no spawn
        # durations, zero processed) means "no token data" — a legacy-only re-run:
        # skip the merge and leave schema_version at 1 (AC 5). This is DISTINCT from
        # an account-tokens.sh error (the else branch below): the no-data skip is
        # benign and leaves today's schema unchanged with no _note, whereas a
        # detectable error gets a stderr warning + a distinguishing _tokens_note.
        tokens_have_data=$(printf '%s' "$tokens_json" | jq -r '
            ((.conductor_tokens.confidence // "unavailable") != "unavailable")
            or ((.delegate_tokens.confidence // "unavailable") != "unavailable")
            or ((.reviewer_tokens.confidence // "unavailable") != "unavailable")
            or ((.checkpoints.entries | length) > 0)
            or ((.wall_clock.active_spawn_time_s.value // 0) != 0)
            or ((.tokens.processed_total.value // 0) != 0)
            or (([.spawn_tokens[] | select(.tokens != null)] | length) > 0)
        ' 2>/dev/null || echo false)
        # A valid aggregator contract is authoritative data even when every
        # transcript contains a legitimate, structurally-complete zero.
        [ "$posthoc_usable" -eq 1 ] && tokens_have_data=true

        if [ "$tokens_have_data" = "true" ]; then
            # (a) Merge the four top-level blocks (same pattern as the memory merge),
            # PLUS the fragment's `_notes` breadcrumb when present. account-tokens.sh
            # emits `_notes` (an array of strings) when it zeroes a non-object (scalar)
            # `tokens` event or skips a torn line — otherwise it is absent. Carry it
            # into accounting.json so the observation phase can see a malformed event
            # was silently counted as 0, not just a transient stderr DEBUG line
            # (pre-eval-hardening Challenger W1). Conditional so a clean run adds no
            # `_notes` key and stays byte-for-byte unchanged (`$tok._notes // []` is
            # `[]` when absent → length 0 → the empty-object branch, no key added).
            # delegate_tokens / reviewer_tokens (#26) forward alongside
            # conductor_tokens — account-tokens.sh always emits all three role
            # blocks (a v1 run gets the two new ones as unavailable/zero blocks,
            # exactly like conductor_tokens today). Without this forwarding the two
            # new blocks are dropped at the merge and never reach accounting.json,
            # defeating #26's "done when" (a v2 run's accounting.json must carry the
            # Delegate + reviewer shares). Additive keys the consumers tolerate.
            jq --argjson tok "$tokens_json" \
               '. + {tokens: $tok.tokens,
                     conductor_tokens: $tok.conductor_tokens,
                     delegate_tokens: $tok.delegate_tokens,
                     reviewer_tokens: $tok.reviewer_tokens,
                     wall_clock: $tok.wall_clock,
                     checkpoints: $tok.checkpoints}
                  + (if (($tok._notes // []) | length) > 0
                     then {_notes: $tok._notes} else {} end)' \
               "$tmp_out" > "${tmp_out}.tok" && mv "${tmp_out}.tok" "$tmp_out"

            # (b) Enrich each specialist_spawns[] entry from the spawn_tokens map.
            # Pairing key is the composite role+"-"+attempt — attempt_id is NOT a leaf
            # in specialist_spawns[] (it is account-run.sh's internal dedup key). The
            # composite matches the deterministic attempt_id format in
            # docs/run-accounting.md § A and the spawn_tokens map keys. Each field is
            # merged only when non-null: a started spawn with no matched
            # SPAWN-TOKEN-EVENT (mid-run or unmatched) has null tokens/turns in the
            # map, and `null | with_entries` would otherwise crash the whole write.
            jq --argjson st "$tokens_json" --argjson aids "$spawn_attempt_ids_json" '
              # Pair each spawn to its token record on the attempt_id § 6 ACTUALLY PARSED
              # (carried index-aligned in $aids), NOT a reconstructed role+"-"+attempt
              # composite. § 6 accepts descriptive attempt_ids (e.g. challenger-r1-1) and
              # the hooks / account-tokens.sh key spawn_tokens by that verbatim id; the
              # composite would rebuild "challenger-1", miss the record, and silently drop
              # at/started_at/duration_s/turns/tokens/rework (W1). $aids is an internal
              # pairing channel only — attempt_id is never emitted as a specialist_spawns[]
              # leaf. Fall back to the composite when the parsed id is unavailable (a legacy
              # line) or the parallel array is not length-aligned; for a conformant composite
              # id the parsed id EQUALS the composite, so behavior is unchanged.
              (($aids | length) == (.specialist_spawns | length)) as $aligned
              | .specialist_spawns as $spawns
              | .specialist_spawns = [
                  range(0; ($spawns | length)) as $i
                  | $spawns[$i] as $spawn
                  | (if $aligned then $aids[$i] else null end) as $parsed_aid
                  | (if ($parsed_aid != null and ($parsed_aid | type) == "string" and ($parsed_aid | length) > 0)
                     then $parsed_aid
                     else ($spawn.role.value + "-" + ($spawn.attempt.value | tostring)) end) as $aid
                  | ($st.spawn_tokens[$aid]) as $stk
                  | if $stk == null then $spawn
                    else
                      $spawn
                      + {rework: ($stk.rework // false)}
                      + (if $stk.at         != null then {at:         {value: $stk.at,         confidence: "exact"}} else {} end)
                      + (if $stk.started_at != null then {started_at: {value: $stk.started_at, confidence: "exact"}} else {} end)
                      + (if $stk.duration_s != null then {duration_s: $stk.duration_s} else {} end)
                      + (if $stk.turns      != null then {turns:      {value: $stk.turns,      confidence: "exact"}} else {} end)
                      + (if $stk.tokens     != null
                         then {tokens: ($stk.tokens
                                 | with_entries(
                                     .key as $k
                                     | .value = {value: .value,
                                         confidence: (if $k == "output" then "estimated"
                                                      elif (($stk._partial_fields // []) | index($k)) != null then "partial"
                                                      else "exact" end)}))}
                         else {} end)
                    end
                ]
            ' "$tmp_out" > "${tmp_out}.enrich" && mv "${tmp_out}.enrich" "$tmp_out"

            # (b2) One-source authoritative per-leg write. attempt_id is the
            # required key (carried by the existing index-aligned internal
            # array). agent_id is only a consistency check when both sources
            # have a value; disagreement keeps the post-hoc number but marks it
            # suspect instead of silently pairing two different agents.
            if [ "$posthoc_usable" -eq 1 ] && \
               jq --slurpfile ph "$posthoc_frag" \
                  --argjson aids "$spawn_attempt_ids_json" \
                  --argjson live_agents "$posthoc_live_agents" '
                 $ph[0] as $posthoc
                 | .conductor_tokens = $posthoc.conductor
                 | .delegate_tokens = $posthoc.delegate
                 | .specialist_spawns as $spawns
                 | (($aids | length) == ($spawns | length)) as $aligned
                 | .specialist_spawns = [
                     range(0; ($spawns | length)) as $i
                     | $spawns[$i] as $spawn
                     | (if $aligned then $aids[$i] else null end) as $aid
                     | ([ $posthoc.specialists[]
                          | select($aid != null and .attempt_id == $aid) ] | .[0]) as $agg
                     | if $agg == null then $spawn
                       else
                         ($live_agents[$aid] // null) as $live_agent
                         | (($live_agent != null) and ($agg.agent_id != null)
                            and ($live_agent != $agg.agent_id)) as $agent_mismatch
                         | (if $agent_mismatch then "suspect"
                            else ($agg.confidence // "unavailable") end) as $disposition
                         | ([ ($agg._note // empty),
                              (if $agent_mismatch
                               then "post-hoc attempt_id \($aid) agent mismatch: live \($live_agent) != transcript \($agg.agent_id) — authoritative token figure surfaced as suspect"
                               else empty end) ] | join("; ")) as $agg_note
                         | $spawn
                           + {tokens: ($agg.tokens | with_entries(
                                 .value = {value:.value,confidence:$disposition})),
                              turns: {value:($agg.turns // 0),confidence:$disposition},
                              confidence:$disposition}
                           + (if $agg_note != ""
                              then {_note: ([($spawn._note // empty),$agg_note]
                                            | map(select(. != "")) | join("; "))}
                              else {} end)
                       end
                   ]
                 # Null-attempt rows have no safe work-shape merge key. Surface
                 # each once in the established unattributed representation.
                 | .tokens.unattributed_records = [
                     $posthoc.specialists[] | select(.attempt_id == null)
                   ]
               ' "$tmp_out" > "${tmp_out}.posthoc"; then
                mv "${tmp_out}.posthoc" "$tmp_out"
                posthoc_merged=1
            else
                rm -f "${tmp_out}.posthoc"
            fi

            # (c) Bump schema_version to 2 — the merge succeeded and the output now
            # carries the Bundle 11 sections.
            jq '.schema_version = 2' "$tmp_out" > "${tmp_out}.v2" && mv "${tmp_out}.v2" "$tmp_out"

            # W4 step 3. Persist only after the authoritative replacement landed.
            # On a true no-op, retain the original accounted_at observation too;
            # otherwise that volatile leaf alone would defeat AC8 byte identity.
            if [ "$posthoc_merged" -eq 1 ]; then
                posthoc_scope_note=$(jq -r 'if (._scope_note | type) == "string" then ._scope_note else empty end' \
                    "$posthoc_frag" 2>/dev/null || echo "")
                jq --arg until "$posthoc_bound" \
                   --argjson basis "$posthoc_basis" \
                   --arg scope_note "$posthoc_scope_note" \
                   --argjson reuse "$posthoc_reuse_bound" \
                   --argjson prior_accounted_at "$posthoc_prior_accounted_at" '
                     . + {_posthoc:
                       ({run_ended_at:$until,basis:$basis}
                        + (if $scope_note != "" then {scope_note:$scope_note} else {} end))}
                     | if $reuse and $prior_accounted_at != null
                       then .run.accounted_at = $prior_accounted_at else . end
                   ' "$tmp_out" > "${tmp_out}.posthoc-meta" \
                   && mv "${tmp_out}.posthoc-meta" "$tmp_out"
            fi
        else
            # Valid JSON but no token data → legacy-only re-run. Leave schema at 1
            # and emit today's schema unchanged — EXCEPT (F4, audit) when the
            # fragment carries a non-empty `_notes` breadcrumb. That is the case of
            # a run whose ONLY token data was a malformed scalar event (all totals
            # zero, no conductor line, unparseable spawn timestamps): tokens_have_data
            # is false so the schema-2 merge is skipped, yet account-tokens.sh DID
            # emit a `_notes` breadcrumb about the malformed event. Without this the
            # breadcrumb is dropped and the run is indistinguishable from a genuine
            # legacy no-token run. Attach `_notes` as a top-level breadcrumb while
            # keeping schema_version at 1 (do NOT flip to schema 2 — AC 5 backward-
            # compat for a GENUINE legacy run must hold, and a legacy run has no
            # `_notes`, so this stays inert there). One conditional.
            if printf '%s' "$tokens_json" | jq -e '((._notes // []) | length) > 0' >/dev/null 2>&1; then
                jq --argjson tok "$tokens_json" '. + {_notes: $tok._notes}' \
                    "$tmp_out" > "${tmp_out}.nnote" && mv "${tmp_out}.nnote" "$tmp_out"
            fi
        fi
    else
        # account-tokens.sh present+executable but the invocation failed or emitted
        # non-JSON — a detectable error (broken SCRIPT_DIR co-location, a jq fault in
        # the consumer, …). Warn to stderr, skip the merge (schema stays 1), and record
        # a distinguishing _tokens_note so the skip is not mistaken for a clean
        # no-token-data run.
        echo "[account-run] WARNING: account-tokens.sh failed or returned non-JSON — token metrics skipped; accounting.json emitted at schema_version 1" >&2
        jq '. + {"_tokens_note": "token-metrics merge skipped — account-tokens.sh failed or returned invalid JSON (see stderr); an error path, not a no-token-data run"}' \
            "$tmp_out" > "${tmp_out}.tnote" && mv "${tmp_out}.tnote" "$tmp_out"
    fi
fi
# else: account-tokens.sh absent or not executable → backward compat, today's schema
# unchanged (schema_version 1), silent — the pre-Bundle-11 install baseline.

# mktemp creates the temp file 0600; chmod to 0644 so the emitted accounting.json is
# world-readable per a normal umask 022 (a reader on a different uid, e.g. CI, can read it).
chmod 644 "$tmp_out"
mv "$tmp_out" "$RUN_DIR/accounting.json"
# tmp_out moved into place; clear so the EXIT trap does not try to rm a now-final file.
tmp_out=""

echo "[account-run] wrote $RUN_DIR/accounting.json"
exit 0
