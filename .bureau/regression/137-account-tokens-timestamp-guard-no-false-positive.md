name: account-tokens timestamp-integrity guard — NO false positive: a legitimate run whose narrative SPAWN-EVENT times agree with the hook SPAWN-TOKEN-EVENT times (same date, within tolerance) reads "exact"; and (W1) a round-hour narrative that an agreeing hook vouches for still reads "exact" — the all-round-hour tell is a fallback that yields to hook evidence
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ts-clean"
  mkdir -p "$RP"
  # A normal run. Narrative terminal SPAWN-EVENT `at` and the same-attempt_id hook
  # SPAWN-TOKEN-EVENT `at` mark the same spawn completion within a few seconds, on
  # the SAME calendar date — the legitimate small gap between the SubagentStop hook
  # firing (`date -u`) and the Conductor logging its terminal line. The `at` values
  # deliberately do NOT all land on the round hour (10:00:00 → 10:12:33 → 10:29:47),
  # and one lone round-hour value (the mage started_at 10:00:00Z) must NOT trip the
  # all-round-hour tell (it requires ALL narrative timestamps to be round). The guard
  # must NOT fire: confidence stays "exact" and no _note is added.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T10:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T10:12:30Z","started_at":"2026-07-05T10:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T10:12:33Z","turns":2,"tokens":{"input":10,"cache_creation":20,"cache_read":30,"processed":500,"output":40}}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T10:12:30Z","rework":false}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T10:29:47Z","started_at":"2026-07-05T10:12:30Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-1","agent_id":"agent-c1","at":"2026-07-05T10:29:49Z","turns":3,"tokens":{"input":5,"cache_creation":10,"cache_read":15,"processed":300,"output":20}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T10:35:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage","challenger"],"phase_status":"complete","critic_loops":{"mage":1,"challenger":1}}' > "$RP/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # Load-bearing false-positive guard: the guard does NOT fire on a legitimate run.
  # confidence stays "exact" (durations: mage 750s + challenger 1037s = 1787s), and
  # no timestamp-integrity _note is present.
  jq -e '
    .schema_version == 2 and
    .wall_clock.active_spawn_time_s.value == 1787 and
    .wall_clock.active_spawn_time_s.confidence == "exact" and
    (.wall_clock.active_spawn_time_s | has("_note") | not)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  # --- W1 corner: round-hour narrative BUT an AGREEING hook must stay "exact" ----
  # The all-round-hour tell is a genuine FALLBACK, not an unconditional signal. Here
  # the narrative spawn spans 10:00:00Z → 11:00:00Z — BOTH exactly on the round hour
  # (the all-round-hour heuristic would fire in isolation) — but the hook
  # SPAWN-TOKEN-EVENT `at` 11:00:03Z AGREES (same date, +3s within tolerance): an
  # independent unfakeable clock has vouched those times are REAL. Round-ness alone
  # must NOT override that. confidence stays "exact", no _note.
  RP2="$TMPF/ts-round-but-vouched"
  mkdir -p "$RP2"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T10:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T11:00:00Z","started_at":"2026-07-05T10:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-05T11:00:03Z","turns":2,"tokens":{"input":10,"cache_creation":20,"cache_read":30,"processed":500,"output":40}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-05T11:05:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP2/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage"],"phase_status":"complete","critic_loops":{"mage":1}}' > "$RP2/state.json"
  bash "$ROOT/scripts/account-run.sh" "$RP2" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '
    .schema_version == 2 and
    .wall_clock.active_spawn_time_s.value == 3600 and
    .wall_clock.active_spawn_time_s.confidence == "exact" and
    (.wall_clock.active_spawn_time_s | has("_note") | not)
  ' "$RP2/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation 1: tighten the hook-cross-check tolerance from 900s to 0s (`.delta_s > 0`)
  # and the 3s legitimate gap between narrative and hook times trips a false positive
  # → confidence flips to "suspect" and the first block's `== "exact"` assertion fails.
  # Mutation 2 (W1): drop the `$any_hook_agrees` gate — revert `$ts_fabricated` to
  # `$hook_disagree or $all_round_hour` — and the W1-corner block's round-hour spawn
  # trips "suspect" despite its agreeing hook → that block's `== "exact"` fails.
expected: exit 0; stdout "PASS"; block 1: value=1787 confidence="exact" no _note; block 2 (W1 corner): round-hour narrative + agreeing hook → value=3600 confidence="exact" no _note — the round-hour tell yields to vouching-hook evidence
phase: 04 · feature
owner: timestamp-exact-wash-guard / account-tokens.sh timestamp-integrity false-positive guard
