name: grill-checkpoint-delegate-registration
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  BRIDGE="$ROOT/docs/delegate-bridge.md"
  V2="$ROOT/docs/delegate-bridge/v2-integrated.md"
  ORCH="$ROOT/agents/orchestrator.md"
  DELEGATE="$ROOT/agents/delegate.md"

  grep -q 'pre-spec grill' "$BRIDGE" \
    || { echo "FAIL: bridge does not name pre-spec grill"; exit 1; }
  grep -q 'checkpoint-type: routine' "$BRIDGE" \
    || { echo "FAIL: bridge does not classify grill as routine type"; exit 1; }
  grep -q 'Do not invent `checkpoint-type: grill`' "$BRIDGE" \
    || { echo "FAIL: bridge missing no-new-type rule"; exit 1; }
  grep -q 'no `checkpoint-subtype: grill`' "$V2" \
    || { echo "FAIL: v2 module missing no-new-subtype rule"; exit 1; }
  grep -q 'Pre-spec grill checkpoint' "$ORCH" \
    || { echo "FAIL: orchestrator missing pre-spec grill checkpoint section"; exit 1; }
  grep -q 'do not invent a `grill`' "$ORCH" \
    || { echo "FAIL: orchestrator missing no-new-type rule"; exit 1; }
  grep -q 'checkpoint type or a new escalation signal' "$ORCH" \
    || { echo "FAIL: orchestrator missing no-new-signal rule"; exit 1; }
  grep -q 'pre-spec grill checkpoint is routine for bridge machinery' "$DELEGATE" \
    || { echo "FAIL: Delegate missing grill routine-machinery note"; exit 1; }
  if awk '/^## Escalation signals/,/^## Verdict/' "$DELEGATE" | grep -q '^11\.'; then
    echo "FAIL: Delegate added an eleventh escalation signal"
    exit 1
  fi
  echo "PASS"
  # Mutation note: adding a grill checkpoint type/subtype, deleting the routine
  # registration, or adding signal 11 makes this fixture fail.
expected: exit 0; stdout "PASS"; grill checkpoints are registered through existing Delegate routine/genuine-fork machinery with no new type or escalation signal.
phase: 01 · feature (Bundle 34)
owner: docs/delegate-bridge.md + docs/delegate-bridge/v2-integrated.md + agents/orchestrator.md + agents/delegate.md
