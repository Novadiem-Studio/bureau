name: account-run — non-object snapshot (FIX B): bare number and bare array both degrade usage_snapshot to unavailable, exit 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # sub-case A: bare number snapshot
  RP="$TMPF/nonobj-num"
  mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP/state.json"
  printf '42' > "$TMPF/nonobj-num.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/nonobj-num.json" bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.stale.value == null and .usage_snapshot.present.value == false and .usage_snapshot.age_seconds.confidence == "unavailable"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # sub-case B: bare array snapshot
  RP2="$TMPF/nonobj-arr"
  mkdir -p "$RP2"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}' > "$RP2/state.json"
  printf '[]' > "$TMPF/nonobj-arr.json"
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/nonobj-arr.json" bash "$ROOT/scripts/account-run.sh" "$RP2" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.usage_snapshot.stale.value == null and .usage_snapshot.present.value == false and .usage_snapshot.age_seconds.confidence == "unavailable"' "$RP2/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; both sub-cases: usage_snapshot.stale.value=null, present.value=false, age_seconds.confidence=unavailable
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
