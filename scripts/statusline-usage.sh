#!/usr/bin/env bash
# statusline-usage.sh — Claude Code statusLine command.
#
# Claude Code pipes a JSON payload on stdin after each API response. For Claude
# Max/Pro it includes `rate_limits` (5-hour + 7-day windows). We do two things:
#   1. Write ~/.novadiem/usage-snapshot.json (the shape the bureau already reads)
#      so the Conductor can route models by real subscription usage.
#   2. Print a compact status line so the numbers are visible.
#
# This REPLACES the retired codexbar poller. No keychain, no third-party app:
# Claude Code itself (the token owner) hands us the numbers, so it never prompts.
#
# rate_limits only appears AFTER the first API response of a session, so before
# that we leave the last good snapshot in place.

set -uo pipefail

SNAPSHOT="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "[usage: jq missing]"
  exit 0
fi

model="$(printf '%s' "$input"      | jq -r '.model.display_name // .model.id // "?"')"
five_used="$(printf '%s' "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')"
five_reset="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')"
week_used="$(printf '%s' "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')"
week_reset="$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')"

now="$(date -u +%s)"
iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# epoch -> "Xd Yh" (quoted JSON string), or null
resets_in() {
  local target="$1"
  [ -z "$target" ] && { printf 'null'; return; }
  local d=$(( target - now )); [ "$d" -lt 0 ] && d=0
  printf '"%dd %dh"' $(( d/86400 )) $(( (d%86400)/3600 ))
}

# Write the snapshot only when we actually have rate-limit data.
if [ -n "$five_used" ] || [ -n "$week_used" ]; then
  sess_used="$(printf '%.0f' "${five_used:-0}" 2>/dev/null || echo 0)"
  week_used_r="$(printf '%.0f' "${week_used:-0}" 2>/dev/null || echo 0)"
  sess_left=$(( 100 - sess_used ))
  week_left=$(( 100 - week_used_r ))
  sess_resets_in="$(resets_in "${five_reset:-}")"
  week_resets_in="$(resets_in "${week_reset:-}")"

  tmp="$(mktemp)"
  cat > "$tmp" <<JSON
{
  "polledAt": "$iso",
  "source": "claude-code-statusline",
  "ok": true,
  "providersRequested": "claude",
  "providers": [],
  "claude": {
    "loginMethod": "Claude Max",
    "sessionLeftPercent": $sess_left,
    "sessionUsedPercent": $sess_used,
    "sessionWindowMinutes": 300,
    "sessionResetsIn": $sess_resets_in,
    "weeklyLeftPercent": $week_left,
    "weeklyUsedPercent": $week_used_r,
    "weeklyResetsIn": $week_resets_in,
    "weeklyPaceDeficitPercent": null,
    "weeklyRunsOutIn": null,
    "sonnetLeftPercent": null,
    "sonnetUsedPercent": null,
    "sonnetResetsIn": null,
    "sonnetBurnTargetLeftPercent": null,
    "sonnetBurnMode": false
  },
  "rateLimits": {
    "fiveHour": { "usedPercent": ${five_used:-null}, "resetsAt": ${five_reset:-null} },
    "sevenDay": { "usedPercent": ${week_used:-null}, "resetsAt": ${week_reset:-null} }
  }
}
JSON
  mkdir -p "$(dirname "$SNAPSHOT")"
  mv -f "$tmp" "$SNAPSHOT" 2>/dev/null
fi

# Compact, visible status line
printf '%s' "$model"
[ -n "$five_used" ] && printf '  ·  5h %s%%' "$(printf '%.0f' "$five_used" 2>/dev/null)"
[ -n "$week_used" ] && printf '  ·  wk %s%%' "$(printf '%.0f' "$week_used" 2>/dev/null)"
