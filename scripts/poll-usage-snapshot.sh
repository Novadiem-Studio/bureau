#!/usr/bin/env bash
# Poll CodexBar for Claude usage and write a shared snapshot.
# The Conductor reads the snapshot instead of spawning codexbar per checkpoint.
#
# Env:
#   NOVADIEM_USAGE_SNAPSHOT_PATH  default: ~/.novadiem/usage-snapshot.json
#   NOVADIEM_USAGE_PROVIDERS      default: claude  (codexbar --provider value)
#   CODEXBAR_BIN                  default: codexbar on PATH, else /usr/local/bin/codexbar

set -euo pipefail

SNAPSHOT_PATH="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
PROVIDERS="${NOVADIEM_USAGE_PROVIDERS:-claude}"
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

mkdir -p "$(dirname "$SNAPSHOT_PATH")"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/usage-snapshot.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

providers_json="$tmpdir/providers.json"
if ! "$CODEXBAR_BIN" usage --provider "$PROVIDERS" --format json >"$providers_json" 2>"$tmpdir/codexbar.err"; then
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
else
  jq -n \
    --arg polledAt "$POLLED_AT" \
    --arg providers "$PROVIDERS" \
    --slurpfile raw "$providers_json" \
    '
      ($raw[0] // []) as $providers
      | ([$providers[] | select(.provider == "claude") | .usage][0]) as $u
      | {
          polledAt: $polledAt,
          source: "codexbar",
          ok: true,
          providersRequested: $providers,
          providers: $providers,
          claude: (
            if $u == null then null
            else {
                loginMethod: ($u.loginMethod // $u.identity.loginMethod // null),
                updatedAt: ($u.updatedAt // null),
                sessionUsedPercent: ($u.primary.usedPercent // null),
                sessionWindowMinutes: ($u.primary.windowMinutes // null),
                weeklyUsedPercent: ($u.secondary.usedPercent // null),
                weeklyResetsAt: ($u.secondary.resetsAt // null),
                weeklyResetDescription: ($u.secondary.resetDescription // null),
                monthlyUsedPercent: ($u.tertiary.usedPercent // null),
                monthlyResetsAt: ($u.tertiary.resetsAt // null)
              }
            end
          )
        }
    ' >"$tmpdir/snapshot.json"
fi

mv "$tmpdir/snapshot.json" "$SNAPSHOT_PATH"
