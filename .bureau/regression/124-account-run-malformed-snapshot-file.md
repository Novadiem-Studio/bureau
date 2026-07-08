name: account-run — malformed snapshot file (FIX A): unparseable JSON file degrades all usage_snapshot fields to unavailable, exits 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/16-malformed-snapshot-file"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf 'this is { not valid json' > "$TMPF/malformed.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/malformed.json" bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.polled_at.confidence == "unavailable" and .usage_snapshot.age_seconds.confidence == "unavailable" and .usage_snapshot.stale.confidence == "unavailable" and .cost.quota_gauge.confidence == "unavailable"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.stale.value == null and .usage_snapshot.present.value == false' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; all usage_snapshot confidences=unavailable, stale.value=null, present.value=false
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
