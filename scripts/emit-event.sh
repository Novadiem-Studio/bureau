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

# ── Helper: emit missing-field error and exit 1 (nothing to stdout) ────────────
missing() {
  printf 'missing field: %s\n' "$1" >&2
  exit 1
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
        ;;
      resolved)
        [ -n "$decision" ] || missing "decision"
        payload=$(jq -cn \
          --arg id       "$id" \
          --arg status   "$status" \
          --arg decision "$decision" \
          --arg at       "$at" \
          '{id: $id, status: $status, decision: $decision, at: $at}')
        ;;
      *)
        printf 'missing field: status must be raised or resolved (got: %s)\n' "$status" >&2
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
        ;;
      closed)
        [ -n "$fix_ref" ]        || missing "fix_ref"
        [ -n "$closed_at_round" ] || missing "closed_at_round"
        payload=$(jq -cn \
          --argjson round           "$round" \
          --arg     id              "$id" \
          --arg     status          "$status" \
          --arg     fix_ref         "$fix_ref" \
          --argjson closed_at_round "$closed_at_round" \
          --arg     at              "$at" \
          '{round: $round, id: $id, status: $status, fix_ref: $fix_ref, closed_at_round: $closed_at_round, at: $at}')
        ;;
      *)
        printf 'missing field: blocker-event status must be raised or closed (got: %s)\n' "$status" >&2
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
