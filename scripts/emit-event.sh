#!/bin/sh
# emit-event.sh — emit one valid event line to stdout.
#
# Usage: emit-event.sh <event-type> [--flags...]
#
# FR 7 / hook-context invokability: ALL input comes from argv (named flags) only.
# No tty, no interactive prompts, no dependence on Claude session state. A
# PostToolUse/PreToolUse hook context produces byte-identical output to an
# interactive run.
#
# Design pattern (mirrors log-append.sh): shell computes the clock, jq composes JSON.
#   at=$(date -u +%Y-%m-%dT%H:%M:%SZ)  — never LLM-typed; jq never generates the stamp
#   JSON composed with jq --arg/--argjson flags, never hand-typed
#
# EC 11 — Nonce-free by construction: no nonce field in any emitted schema.
#
# Exit codes:
#   0   one event line emitted to stdout
#   1   missing required field (stderr: "missing field: <name>"; stdout: empty)
#   2   unknown event type or bad usage

PATH=/usr/bin:$PATH  # EC 10 — ugrep guard; also needed for date

usage() {
  cat >&2 <<'EOF'
Usage: emit-event.sh <event-type> [--flags...]

Event types:
  spawn-event
    --role <str> --agent <str> --configured-model <str> --actual-model <str>
    --attempt <int> --attempt-id <str> --status <str>

  checkpoint-event
    --id <str> --status raised|resolved [--decision <str>]   (required on resolved)

  blocker-event
    raised:  --round <int> --id <str> --status raised --root <str> --gist <str>
    closed:  --round <int> --id <str> --status closed --fix-ref <str> --closed-at-round <int>
EOF
  exit 2
}

# ── Parse event type ──────────────────────────────────────────────────────────
[ "$#" -ge 1 ] || usage
event_type="$1"; shift

# ── Shell-computed timestamp (EC 11 — never LLM-typed) ────────────────────────
at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Flag parser (common to all event types) ────────────────────────────────────
role="" agent="" configured_model="" actual_model="" attempt="" attempt_id=""
status="" id="" decision="" round="" root="" gist="" fix_ref="" closed_at_round=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --role)             role="$2";             shift 2 ;;
    --agent)            agent="$2";            shift 2 ;;
    --configured-model) configured_model="$2"; shift 2 ;;
    --actual-model)     actual_model="$2";     shift 2 ;;
    --attempt)          attempt="$2";          shift 2 ;;
    --attempt-id)       attempt_id="$2";       shift 2 ;;
    --status)           status="$2";           shift 2 ;;
    --id)               id="$2";               shift 2 ;;
    --decision)         decision="$2";         shift 2 ;;
    --round)            round="$2";            shift 2 ;;
    --root)             root="$2";             shift 2 ;;
    --gist)             gist="$2";             shift 2 ;;
    --fix-ref)          fix_ref="$2";          shift 2 ;;
    --closed-at-round)  closed_at_round="$2";  shift 2 ;;
    *) echo "emit-event: unknown flag: $1" >&2; usage ;;
  esac
done

# ── Helper: validate numeric flags — accept only non-negative integers ──────────
# Usage: validate_numeric <flag-name> <value>
# Exits 1 if value is non-numeric (nothing emitted to stdout).
validate_numeric() {
  _vn_flag="$1"
  _vn_val="$2"
  case "$_vn_val" in
    ''|*[!0-9]*)
      printf 'invalid value: %s must be a non-negative integer (got: %s)\n' "$_vn_flag" "$_vn_val" >&2
      exit 1
      ;;
  esac
}

# ── Helper: emit missing-field error and exit 1 (nothing to stdout) ────────────
missing() {
  printf 'missing field: %s\n' "$1" >&2
  exit 1
}

# ── Helper: post-composition guard — exit 1 if payload is empty or not a JSON object ──
# Usage: guard_payload <payload-var> <event-type>
# Prints nothing to stdout on failure; emits error to stderr; exits 1.
guard_payload() {
  _gp_payload="$1"
  _gp_type="$2"
  if [ -z "$_gp_payload" ]; then
    printf 'emit-event: %s composition produced empty payload\n' "$_gp_type" >&2
    exit 1
  fi
  if ! printf '%s\n' "$_gp_payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
    printf 'emit-event: %s composition produced invalid JSON\n' "$_gp_type" >&2
    exit 1
  fi
}

# ── Dispatch on event type ─────────────────────────────────────────────────────
case "$event_type" in

  # ── spawn-event ────────────────────────────────────────────────────────────
  spawn-event)
    [ -n "$role" ]             || missing "role"
    [ -n "$agent" ]            || missing "agent"
    [ -n "$configured_model" ] || missing "configured_model"
    [ -n "$actual_model" ]     || missing "actual_model"
    [ -n "$attempt" ]          || missing "attempt"
    [ -n "$attempt_id" ]       || missing "attempt_id"
    [ -n "$status" ]           || missing "status"
    # Numeric validation — must happen before jq composition
    validate_numeric "--attempt" "$attempt"
    # Compose JSON with jq — no hand-typed JSON (EC rule: shell computes, jq composes)
    payload=$(jq -cn \
      --arg    role             "$role" \
      --arg    agent            "$agent" \
      --arg    configured_model "$configured_model" \
      --arg    actual_model     "$actual_model" \
      --argjson attempt         "$attempt" \
      --arg    attempt_id       "$attempt_id" \
      --arg    status           "$status" \
      --arg    at               "$at" \
      '{role:             $role,
        agent:            $agent,
        configured_model: $configured_model,
        actual_model:     $actual_model,
        attempt:          $attempt,
        attempt_id:       $attempt_id,
        status:           $status,
        at:               $at}')
    guard_payload "$payload" "spawn-event"
    printf 'SPAWN-EVENT: %s\n' "$payload"
    ;;

  # ── checkpoint-event ───────────────────────────────────────────────────────
  checkpoint-event)
    [ -n "$id" ]     || missing "id"
    [ -n "$status" ] || missing "status"
    case "$status" in
      raised)
        payload=$(jq -cn \
          --arg id     "$id" \
          --arg status "$status" \
          --arg at     "$at" \
          '{id: $id, status: $status, at: $at}')
        guard_payload "$payload" "checkpoint-event/raised"
        ;;
      resolved)
        [ -n "$decision" ] || missing "decision"
        payload=$(jq -cn \
          --arg id       "$id" \
          --arg status   "$status" \
          --arg decision "$decision" \
          --arg at       "$at" \
          '{id: $id, status: $status, decision: $decision, at: $at}')
        guard_payload "$payload" "checkpoint-event/resolved"
        ;;
      *)
        printf 'invalid value: status must be raised or resolved (got: %s)\n' "$status" >&2
        exit 1
        ;;
    esac
    printf 'CHECKPOINT-EVENT: %s\n' "$payload"
    ;;

  # ── blocker-event ──────────────────────────────────────────────────────────
  blocker-event)
    [ -n "$round" ]  || missing "round"
    [ -n "$id" ]     || missing "id"
    [ -n "$status" ] || missing "status"
    # Numeric validation — must happen before jq composition
    validate_numeric "--round" "$round"
    case "$status" in
      raised)
        [ -n "$root" ] || missing "root"
        [ -n "$gist" ] || missing "gist"
        payload=$(jq -cn \
          --argjson round "$round" \
          --arg     id    "$id" \
          --arg     status "$status" \
          --arg     root   "$root" \
          --arg     gist   "$gist" \
          --arg     at     "$at" \
          '{round: $round, id: $id, status: $status, root: $root, gist: $gist, at: $at}')
        guard_payload "$payload" "blocker-event/raised"
        ;;
      closed)
        [ -n "$fix_ref" ]        || missing "fix_ref"
        [ -n "$closed_at_round" ] || missing "closed_at_round"
        validate_numeric "--closed-at-round" "$closed_at_round"
        payload=$(jq -cn \
          --argjson round           "$round" \
          --arg     id              "$id" \
          --arg     status          "$status" \
          --arg     fix_ref         "$fix_ref" \
          --argjson closed_at_round "$closed_at_round" \
          --arg     at              "$at" \
          '{round: $round, id: $id, status: $status, fix_ref: $fix_ref, closed_at_round: $closed_at_round, at: $at}')
        guard_payload "$payload" "blocker-event/closed"
        ;;
      *)
        printf 'invalid value: blocker-event status must be raised or closed (got: %s)\n' "$status" >&2
        exit 1
        ;;
    esac
    printf 'BLOCKER-EVENT: %s\n' "$payload"
    ;;

  *)
    printf 'emit-event: unknown event type: %s\n' "$event_type" >&2
    usage
    ;;
esac
