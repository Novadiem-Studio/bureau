#!/usr/bin/env bash
# Poll CodexBar for Claude usage and write a shared snapshot.
# The Conductor reads the snapshot instead of spawning codexbar per checkpoint.
#
# Env:
#   NOVADIEM_USAGE_SNAPSHOT_PATH  default: ~/.novadiem/usage-snapshot.json
#   NOVADIEM_USAGE_PROVIDERS      default: claude  (codexbar --provider value)
#   NOVADIEM_USAGE_INCLUDE_JSON   default: 0 — set 1 for a second OAuth call (raw providers array)
#   CODEXBAR_BIN                  default: codexbar on PATH, else /usr/local/bin/codexbar

set -euo pipefail

SNAPSHOT_PATH="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
PROVIDERS="${NOVADIEM_USAGE_PROVIDERS:-claude}"
INCLUDE_JSON="${NOVADIEM_USAGE_INCLUDE_JSON:-0}"
POLLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if command -v codexbar >/dev/null 2>&1; then
  CODEXBAR_BIN="$(command -v codexbar)"
elif [[ -x "${CODEXBAR_BIN:-/usr/local/bin/codexbar}" ]]; then
  CODEXBAR_BIN="${CODEXBAR_BIN:-/usr/local/bin/codexbar}"
else
  echo "poll-usage-snapshot: codexbar not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "poll-usage-snapshot: jq required" >&2
  exit 1
fi

# Parse CodexBar text output (Sonnet + pace lines are text-only today).
parse_usage_text() {
  local text="$1"
  local line

  SESSION_LEFT=""
  WEEKLY_LEFT=""
  SONNET_LEFT=""
  PACE_DEFICIT=""
  RUNS_OUT_IN=""
  WEEKLY_RESETS_IN=""
  SONNET_RESETS_IN=""
  PLAN=""

  while IFS= read -r line; do
    case "$line" in
      "Session:"*)
        SESSION_LEFT="$(printf '%s' "$line" | sed -n 's/.*: \([0-9][0-9]*\)% left.*/\1/p')"
        ;;
      "Weekly:"*)
        WEEKLY_LEFT="$(printf '%s' "$line" | sed -n 's/.*: \([0-9][0-9]*\)% left.*/\1/p')"
        ;;
      "Sonnet:"*)
        SONNET_LEFT="$(printf '%s' "$line" | sed -n 's/.*: \([0-9][0-9]*\)% left.*/\1/p')"
        ;;
      "Pace:"*)
        PACE_DEFICIT="$(printf '%s' "$line" | sed -n 's/.*\([0-9][0-9]*\)% in deficit.*/\1/p')"
        RUNS_OUT_IN="$(printf '%s' "$line" | sed -n 's/.*Runs out in \(.*\)$/\1/p' | sed 's/ |$//')"
        ;;
      "Plan:"*)
        PLAN="$(printf '%s' "$line" | sed -n 's/^Plan: \(.*\)$/\1/p')"
        ;;
      "Resets in"*)
        if [[ -n "$SONNET_LEFT" && -z "$SONNET_RESETS_IN" ]]; then
          SONNET_RESETS_IN="$(printf '%s' "$line" | sed -n 's/^Resets in \(.*\)$/\1/p')"
        elif [[ -n "$WEEKLY_LEFT" && -z "$WEEKLY_RESETS_IN" ]]; then
          WEEKLY_RESETS_IN="$(printf '%s' "$line" | sed -n 's/^Resets in \(.*\)$/\1/p')"
        fi
        ;;
    esac
  done <<<"$text"
}

left_to_used() {
  local left="$1"
  if [[ -z "$left" ]]; then
    printf 'null'
  else
    printf '%s' "$((100 - left))"
  fi
}

json_num() {
  if [[ -z "${1:-}" ]]; then
    printf 'null'
  else
    printf '%s' "$1"
  fi
}

mkdir -p "$(dirname "$SNAPSHOT_PATH")"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/usage-snapshot.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

text_out="$tmpdir/usage.txt"
if ! "$CODEXBAR_BIN" usage --provider "$PROVIDERS" --no-color >"$text_out" 2>"$tmpdir/codexbar.err"; then
  err="$(tr '\n' ' ' <"$tmpdir/codexbar.err" | sed 's/  */ /g')"
  jq -n \
    --arg polledAt "$POLLED_AT" \
    --arg error "$err" \
    --arg providers "$PROVIDERS" \
    '{
      polledAt: $polledAt,
      source: "codexbar",
      ok: false,
      error: $error,
      providersRequested: $providers,
      providers: [],
      claude: null
    }' >"$tmpdir/snapshot.json"
  mv "$tmpdir/snapshot.json" "$SNAPSHOT_PATH"
  exit 0
fi

parse_usage_text "$(cat "$text_out")"

providers_json="[]"
if [[ "$INCLUDE_JSON" == "1" ]]; then
  if "$CODEXBAR_BIN" usage --provider "$PROVIDERS" --format json >"$tmpdir/providers.json" 2>/dev/null; then
    providers_json="$(cat "$tmpdir/providers.json")"
  fi
fi

session_used="$(left_to_used "$SESSION_LEFT")"
weekly_used="$(left_to_used "$WEEKLY_LEFT")"
sonnet_used="$(left_to_used "$SONNET_LEFT")"

jq -n \
  --arg polledAt "$POLLED_AT" \
  --arg providers "$PROVIDERS" \
  --arg plan "$PLAN" \
  --arg runsOutIn "$RUNS_OUT_IN" \
  --arg weeklyResetsIn "$WEEKLY_RESETS_IN" \
  --arg sonnetResetsIn "$SONNET_RESETS_IN" \
  --argjson providersRaw "$providers_json" \
  --argjson sessionLeft "$(json_num "$SESSION_LEFT")" \
  --argjson weeklyLeft "$(json_num "$WEEKLY_LEFT")" \
  --argjson sonnetLeft "$(json_num "$SONNET_LEFT")" \
  --argjson sessionUsed "$session_used" \
  --argjson weeklyUsed "$weekly_used" \
  --argjson sonnetUsed "$sonnet_used" \
  --argjson paceDeficit "$(json_num "$PACE_DEFICIT")" \
  '{
    polledAt: $polledAt,
    source: "codexbar",
    ok: true,
    providersRequested: $providers,
    providers: $providersRaw,
    claude: {
      loginMethod: (if $plan == "" then null else $plan end),
      sessionLeftPercent: $sessionLeft,
      sessionUsedPercent: $sessionUsed,
      sessionWindowMinutes: 300,
      weeklyLeftPercent: $weeklyLeft,
      weeklyUsedPercent: $weeklyUsed,
      weeklyResetsIn: (if $weeklyResetsIn == "" then null else $weeklyResetsIn end),
      weeklyPaceDeficitPercent: $paceDeficit,
      weeklyRunsOutIn: (if $runsOutIn == "" then null else $runsOutIn end),
      sonnetLeftPercent: $sonnetLeft,
      sonnetUsedPercent: $sonnetUsed,
      sonnetResetsIn: (if $sonnetResetsIn == "" then null else $sonnetResetsIn end),
      sonnetBurnTargetLeftPercent: 25,
      sonnetBurnMode: (
        if $sonnetLeft == null then false
        else ($sonnetLeft > 25)
        end
      )
    }
  }' >"$tmpdir/snapshot.json"

mv "$tmpdir/snapshot.json" "$SNAPSHOT_PATH"
