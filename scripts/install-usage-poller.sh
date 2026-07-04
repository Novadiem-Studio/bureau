#!/usr/bin/env bash
# RETIRED — replaced by scripts/statusline-usage.sh (Claude Code statusLine). Do not run.
# Install a launchd agent that polls CodexBar every 5 minutes.
# Usage: ./scripts/install-usage-poller.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/poll-usage-snapshot.sh"
PLIST_TEMPLATE="$SCRIPT_DIR/com.novadiem.usage-snapshot.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.novadiem.usage-snapshot.plist"
LOG_DIR="${NOVADIEM_USAGE_LOG_DIR:-$HOME/.novadiem/logs}"
LABEL="com.novadiem.usage-snapshot"

chmod +x "$POLL_SCRIPT"

mkdir -p "$LOG_DIR" "$(dirname "${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}")"
mkdir -p "$HOME/Library/LaunchAgents"

sed \
  -e "s|__POLL_SCRIPT__|$POLL_SCRIPT|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$PLIST_TEMPLATE" >"$PLIST_DEST"

if launchctl list 2>/dev/null | grep -q "$LABEL"; then
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

launchctl load "$PLIST_DEST"
"$POLL_SCRIPT"

echo "Installed $PLIST_DEST"
echo "Snapshot: ${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
echo "Logs: $LOG_DIR/usage-poller.{log,err}"
echo "Interval: 300s (5 minutes). Unload with: launchctl unload $PLIST_DEST"
