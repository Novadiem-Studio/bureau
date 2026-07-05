name: account-run AC11 — resolved checkpoint pair yields wait_s exact; raised-only yields null/unavailable and is excluded from human_wait_total_s
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac11"
  mkdir -p "$RP"
  # One resolved pair (design-model: 120s) and one raised-only (orphan) checkpoint.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-a1","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    'CHECKPOINT-EVENT: {"id":"design-model","status":"raised","at":"2026-07-05T00:02:00Z"}' \
    'CHECKPOINT-EVENT: {"id":"design-model","status":"resolved","at":"2026-07-05T00:04:00Z","decision":"proceed"}' \
    'CHECKPOINT-EVENT: {"id":"orphan","status":"raised","at":"2026-07-05T00:05:00Z"}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-c","at":"2026-07-05T00:10:00Z","turns":10,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect"],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # The resolved pair has wait_s exact (120s); the raised-only has wait_s
  # {null, unavailable}; human_wait_total_s counts ONLY the resolved pair (120),
  # so the raised-only never contributes.
  jq -e '
    ([.checkpoints.entries[] | select(.id == "design-model")][0].wait_s.confidence == "exact") and
    ([.checkpoints.entries[] | select(.id == "design-model")][0].wait_s.value == 120) and
    ([.checkpoints.entries[] | select(.id == "orphan")][0].wait_s.value == null) and
    ([.checkpoints.entries[] | select(.id == "orphan")][0].wait_s.confidence == "unavailable") and
    (.checkpoints.human_wait_total_s.value == 120)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: if the raised-only checkpoint leaked into human_wait_total_s, the
  # total would exceed 120 and this fixture fails.
expected: exit 0; stdout "PASS"; resolved pair wait_s=120(exact); raised-only wait_s null(unavailable); human_wait_total_s=120
phase: 05 · feature
owner: Prompt 5 / account-run.sh checkpoint pairing (AC 11)
