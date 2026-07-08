name: account-run — snapshot absent: present=false, stale=null confidence=unavailable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/03-snapshot-absent"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH=/nonexistent/path.json bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.present.value == false and .usage_snapshot.stale.value == null and .usage_snapshot.stale.confidence == "unavailable"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; usage_snapshot.present.value=false, stale.value=null, stale.confidence=unavailable
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
