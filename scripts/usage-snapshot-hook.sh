#!/usr/bin/env bash
# usage-snapshot-hook.sh — Claude Code hook that refreshes the usage snapshot.
#
# WHY THIS EXISTS
# ---------------
# statusline-usage.sh writes ~/.novadiem/usage-snapshot.json, but only where
# Claude Code renders a status line (the terminal CLI). The desktop app's Code
# tab never runs it, so a bureau run driven from the desktop app read whatever
# the last terminal session left behind (issue #109: 11 hours stale, 20% weekly
# used against a live 9%). Hooks DO fire in the desktop app, the CLI and
# subagents, so this hook is the second writer.
#
# A hook payload carries no rate-limit figures, so the numbers come from the
# ClaudeUsage menu-bar app's local API (GET /usage on 127.0.0.1:47291).
#
# RULES
# -----
# - Throttled: at most one fetch per NOVADIEM_USAGE_HOOK_INTERVAL seconds
#   (default 60), keyed on a stamp file, so PostToolUse can fire freely.
# - Never overwrites fresher data: if the snapshot's polledAt is newer than
#   ClaudeUsage's lastUpdated (the status line just wrote), it leaves it alone.
# - Account guard: writes only when ClaudeUsage's accountUUID matches this
#   session's login (CLAUDE_CONFIG_DIR/.claude.json, else ~/.claude.json). On a
#   multi-account machine another account's numbers would route the bureau on
#   the wrong quota, which is worse than a stale file.
# - Silent and non-blocking: every failure exits 0 with no output. Register it
#   with "async": true.
#
# ClaudeUsage reports times in seconds since 2001-01-01 (Apple's reference
# date), not the Unix epoch; APPLE_EPOCH_OFFSET converts them.

set -uo pipefail

SNAPSHOT="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
BASE_URL="${CLAUDE_USAGE_BASE_URL:-http://127.0.0.1:47291}"
INTERVAL="${NOVADIEM_USAGE_HOOK_INTERVAL:-60}"
STAMP="${NOVADIEM_USAGE_HOOK_STAMP:-$HOME/.novadiem/usage-snapshot-hook.stamp}"
APPLE_EPOCH_OFFSET=978307200

# Drain the hook payload; nothing in it is needed.
cat >/dev/null 2>&1 || true

command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

now="$(date -u +%s)"

# Throttle.
if [ -f "$STAMP" ]; then
  last="$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)"
  [ $(( now - last )) -lt "$INTERVAL" ] && exit 0
fi
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || exit 0
touch "$STAMP" 2>/dev/null || exit 0

body="$(curl -s --max-time 2 "${BASE_URL%/}/usage" 2>/dev/null)" || exit 0
[ -n "$body" ] || exit 0

# Account guard.
config_json="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
session_account="$(jq -r '.oauthAccount.accountUuid // empty' "$config_json" 2>/dev/null)"
usage_account="$(printf '%s' "$body" | jq -r '.accountUUID // empty' 2>/dev/null)"
[ -n "$session_account" ] && [ -n "$usage_account" ] || exit 0
[ "$session_account" = "$usage_account" ] || exit 0

# Extract and convert. Any missing number aborts the write.
fields="$(printf '%s' "$body" | jq -r --argjson off "$APPLE_EPOCH_OFFSET" '
  def unix: if type == "number" then (. + $off | floor | tostring) else "" end;
  if (.currentSession.percentage | type) == "number"
     and (.weeklyLimits.allModelsPercentage | type) == "number"
     and (.lastUpdated | type) == "string"
  then
    @sh "sess_used=\(.currentSession.percentage | round) week_used=\(.weeklyLimits.allModelsPercentage | round) sess_reset=\(.currentSession.resetsAt | unix) week_reset=\(.weeklyLimits.resetsAt | unix) usage_updated=\(.lastUpdated)"
  else empty end' 2>/dev/null)"
[ -n "$fields" ] || exit 0
sess_used="" week_used="" sess_reset="" week_reset="" usage_updated=""
eval "$fields"
case "$usage_updated" in *T*Z) ;; *) exit 0 ;; esac

# Freshness guard: keep a snapshot that is newer than ClaudeUsage's data.
if [ -r "$SNAPSHOT" ]; then
  snap_polled="$(jq -r '.polledAt // empty' "$SNAPSHOT" 2>/dev/null)"
  if [ -n "$snap_polled" ] && [[ "$snap_polled" > "$usage_updated" ]]; then
    exit 0
  fi
fi

resets_in() {
  local target="$1"
  [ -z "$target" ] && { printf 'null'; return; }
  local d=$(( target - now )); [ "$d" -lt 0 ] && d=0
  printf '"%dd %dh"' $(( d/86400 )) $(( (d%86400)/3600 ))
}

tmp="$(mktemp "${TMPDIR:-/tmp}/usage-snapshot.XXXXXX" 2>/dev/null)" || exit 0
jq -n \
  --arg polled "$usage_updated" \
  --arg account "$usage_account" \
  --argjson sess_used "$sess_used" \
  --argjson week_used "$week_used" \
  --argjson sess_resets_in "$(resets_in "$sess_reset")" \
  --argjson week_resets_in "$(resets_in "$week_reset")" \
  --argjson sess_reset "${sess_reset:-null}" \
  --argjson week_reset "${week_reset:-null}" '
  {
    polledAt: $polled,
    source: "claudeusage-hook",
    account: $account,
    ok: true,
    providersRequested: "claude",
    providers: [],
    claude: {
      loginMethod: "Claude Max",
      sessionLeftPercent: (100 - $sess_used),
      sessionUsedPercent: $sess_used,
      sessionWindowMinutes: 300,
      sessionResetsIn: $sess_resets_in,
      weeklyLeftPercent: (100 - $week_used),
      weeklyUsedPercent: $week_used,
      weeklyResetsIn: $week_resets_in,
      weeklyPaceDeficitPercent: null,
      weeklyRunsOutIn: null,
      sonnetLeftPercent: null,
      sonnetUsedPercent: null,
      sonnetResetsIn: null,
      sonnetBurnTargetLeftPercent: null,
      sonnetBurnMode: false
    },
    rateLimits: {
      fiveHour: { usedPercent: $sess_used, resetsAt: $sess_reset },
      sevenDay: { usedPercent: $week_used, resetsAt: $week_reset }
    }
  }' > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }

mkdir -p "$(dirname "$SNAPSHOT")" 2>/dev/null
mv -f "$tmp" "$SNAPSHOT" 2>/dev/null || rm -f "$tmp"
exit 0
