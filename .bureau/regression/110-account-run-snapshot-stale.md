name: account-run — snapshot stale: far-past polledAt yields quota_gauge=unavailable, stale.value boolean
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/04-stale-snapshot"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '{' \
    '  "polledAt": "2020-01-01T00:00:00Z",' \
    '  "source": "codexbar",' \
    '  "ok": true,' \
    '  "providersRequested": "claude",' \
    '  "providers": [],' \
    '  "claude": {' \
    '    "sessionUsedPercent": 10,' \
    '    "weeklyUsedPercent": 5,' \
    '    "sonnetUsedPercent": 20' \
    '  }' \
    '}' \
    > "$TMPF/stale.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/stale.json" bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.cost.quota_gauge.confidence == "unavailable" and ((.usage_snapshot.stale.value | type) == "boolean")' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; cost.quota_gauge.confidence=unavailable, usage_snapshot.stale.value is a boolean
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
