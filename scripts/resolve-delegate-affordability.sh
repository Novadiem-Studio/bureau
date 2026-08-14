#!/usr/bin/env bash
# Resolve the Delegate's Claude-only affordability signal. Stdout is one JSON object.

set -u

runtime="${1:-}"
snapshot_path="${2:-$HOME/.novadiem/usage-snapshot.json}"
base_url="${CLAUDE_USAGE_BASE_URL:-http://127.0.0.1:47291}"
base_url="${base_url%/}"

if [ "$runtime" = "openai" ]; then
  printf '%s\n' '{"action":"skip","source":"runtime"}'
  exit 0
fi

body_file=""
cleanup() {
  if [ -n "$body_file" ]; then
    rm -f "$body_file"
  fi
}
trap cleanup EXIT

curl_status=1
http_status=""
body_file="$(mktemp "${TMPDIR:-/tmp}/delegate-affordability.XXXXXX" 2>/dev/null || printf '')"
if [ -n "$body_file" ] && command -v curl >/dev/null 2>&1; then
  http_status="$(
    curl -s --max-time 2 -o "$body_file" -w '%{http_code}' "$base_url/opus" 2>/dev/null
  )"
  curl_status=$?
fi

if [ "$curl_status" -eq 0 ] && [ "$http_status" = "200" ] && command -v jq >/dev/null 2>&1; then
  percent_remaining="$(jq -er '.percentRemaining | select(type == "number")' "$body_file" 2>/dev/null || printf '')"
  if [ -n "$percent_remaining" ]; then
    printf '{"action":"use_quota","source":"live","percent_remaining":%s}\n' "$percent_remaining"
    exit 0
  fi
fi

if [ -r "$snapshot_path" ] && command -v jq >/dev/null 2>&1; then
  percent_remaining="$(jq -er '.claude.weeklyLeftPercent | select(type == "number")' "$snapshot_path" 2>/dev/null || printf '')"
  if [ -n "$percent_remaining" ]; then
    printf '{"action":"use_quota","source":"snapshot","percent_remaining":%s}\n' "$percent_remaining"
    exit 0
  fi
fi

printf '%s\n' '{"action":"default","source":"none"}'
exit 0
