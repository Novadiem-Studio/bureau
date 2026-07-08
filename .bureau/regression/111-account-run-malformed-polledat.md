name: account-run — malformed polledAt: non-ISO8601 field degrades age_seconds and quota_gauge to unavailable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/05-malformed-polledat"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' \
    '{' \
    '  "polledAt": "not-a-date",' \
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
    > "$TMPF/malformed-polledat.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/malformed-polledat.json" bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.age_seconds.value == null and .usage_snapshot.age_seconds.confidence == "unavailable" and .cost.quota_gauge.confidence == "unavailable"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; age_seconds.value=null, age_seconds.confidence=unavailable, quota_gauge.confidence=unavailable
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
