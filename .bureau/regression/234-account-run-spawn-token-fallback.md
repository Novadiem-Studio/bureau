name: account-run — SPAWN-TOKEN-EVENT-only log yields inferred specialist_spawns (fallback), no double-fire when SPAWN-EVENT present
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  AR="$ROOT/scripts/account-run.sh"
  TMPF=$(mktemp -d)

  # ── (a)+(b): a log.md with ONLY SPAWN-TOKEN-EVENT lines (Conductor never emitted
  # the paired SPAWN-EVENT work-shape lines) and a non-empty phases_complete. PRE-FIX
  # this produced specialist_spawns: [] (the zero-spawn signature); POST-FIX the STEP
  # A1 fallback synthesizes one inferred entry per unmatched SPAWN-TOKEN-EVENT.
  RP="$TMPF/fallback"; mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"spellwright-1","agent_id":"agent-sw1","at":"2026-08-09T10:05:00Z","turns":5,"tokens":{"input":42100,"cache_creation":0,"cache_read":0,"processed":42100,"output":3130}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-r1-1","agent_id":"agent-ch1","at":"2026-08-09T10:15:00Z","turns":4,"tokens":{"input":36000,"cache_creation":0,"cache_read":0,"processed":36000,"output":2900}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"systemsmith-1","agent_id":"agent-ss1","at":"2026-08-09T10:30:00Z","turns":8,"tokens":{"input":88000,"cache_creation":0,"cache_read":0,"processed":88000,"output":7000}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-abc","at":"2026-08-09T11:00:00Z","turns":40,"tokens":{"input":50000,"cache_creation":0,"cache_read":0,"processed":50000,"output":5000}}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["analysis","build"],"phase_status":"complete","critic_loops":{"spellwright":1,"challenger":3}}' > "$RP/state.json"
  out=$(bash "$AR" "$RP" 2>/dev/null) || { echo "account-run exited non-zero"; rm -rf "$TMPF"; exit 1; }
  # The existing zero-SPAWN-EVENT warning must still appear (invariant kept loud).
  printf '%s' "$out" | grep -qF '[CLOSE-OUT WARNING]' || { echo "close-out warning missing"; rm -rf "$TMPF"; exit 1; }
  # POST-FIX GREEN: three inferred entries, roles read from attempt_id prefixes, all
  # "inferred"/"unavailable" confidence, and the _specialist_spawns_note names the ids.
  jq -e '
    (.specialist_spawns | length) == 3
    and (.specialist_spawns | map(.role.value) | sort) == ["challenger","spellwright","systemsmith"]
    and (.specialist_spawns | all(.role.confidence == "inferred"))
    and (.specialist_spawns | all(.configured_model.confidence == "unavailable"))
    and (.specialist_spawns | all(.actual_model.confidence == "unavailable"))
    and (.specialist_spawns | all(.reported_status.value == "complete"))
    and (.specialist_spawns | all(has("_note")))
    and (._specialist_spawns_note | test("challenger-r1-1"))
    and (._specialist_spawns_note | test("spellwright-1"))
    and (._specialist_spawns_note | test("systemsmith-1"))
  ' "$RP/accounting.json" > /dev/null || { echo "inferred fallback entries wrong"; rm -rf "$TMPF"; exit 1; }
  # Aggregate token totals are still recovered (specialist 42100+36000+88000 + conductor 50000).
  jq -e '.tokens.processed_total.value == 216100' "$RP/accounting.json" > /dev/null \
    || { echo "aggregate processed_total not recovered"; rm -rf "$TMPF"; exit 1; }
  python3 -c "import json; json.load(open('$RP/accounting.json'))" || { echo "accounting.json invalid"; rm -rf "$TMPF"; exit 1; }

  # ── (c): when SPAWN-EVENT lines ARE present, the fallback must NOT fire — the run
  # gets its real work-shape from SPAWN-EVENT and specialist_spawns is exact, not inferred.
  RP2="$TMPF/present"; mkdir -p "$RP2"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-aaa","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":300,"cache_read":500,"processed":1000,"output":50}}' \
    > "$RP2/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect"],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RP2/state.json"
  bash "$AR" "$RP2" >/dev/null 2>&1 || { echo "account-run (present) non-zero"; rm -rf "$TMPF"; exit 1; }
  jq -e '
    (.specialist_spawns | length) == 1
    and .specialist_spawns[0].role.value == "architect"
    and .specialist_spawns[0].role.confidence == "exact"
    and (.specialist_spawns[0]._note // "" | test("inferred from SPAWN-TOKEN-EVENT") | not)
  ' "$RP2/accounting.json" > /dev/null || { echo "fallback wrongly fired with SPAWN-EVENT present"; rm -rf "$TMPF"; exit 1; }

  # ── (d) PARTIAL-emit: architect emitted via SPAWN-EVENT, challenger + systemsmith only
  # via SPAWN-TOKEN-EVENT. The fallback now runs UNCONDITIONALLY (not just the zero case),
  # so the token-only specialists are recovered as inferred WITHOUT double-counting the
  # architect (which is excluded via its matching SPAWN-EVENT started line). The exact
  # architect keeps its per-spawn tokens; the inferred entries do not get per-spawn tokens
  # (account-tokens.sh keys the token map on SPAWN-EVENT started records).
  RP3="$TMPF/partial"; mkdir -p "$RP3"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"architect-1","agent_id":"agent-arc","at":"2026-07-05T00:01:00Z","turns":5,"tokens":{"input":200,"cache_creation":0,"cache_read":0,"processed":200,"output":50}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"challenger-1","agent_id":"agent-ch1","at":"2026-07-05T00:02:00Z","turns":4,"tokens":{"input":36000,"cache_creation":0,"cache_read":0,"processed":36000,"output":2900}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"systemsmith-1","agent_id":"agent-ss1","at":"2026-07-05T00:03:00Z","turns":8,"tokens":{"input":88000,"cache_creation":0,"cache_read":0,"processed":88000,"output":7000}}' \
    > "$RP3/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect","challenger","systemsmith"],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RP3/state.json"
  out3=$(bash "$AR" "$RP3" 2>&1) || { echo "account-run (partial) non-zero"; rm -rf "$TMPF"; exit 1; }
  # No [CLOSE-OUT WARNING] here — the warning gate still fires ONLY on zero SPAWN-EVENT lines.
  printf '%s' "$out3" | grep -qF '[CLOSE-OUT WARNING]' && { echo "warning wrongly fired in partial-emit"; rm -rf "$TMPF"; exit 1; }
  jq -e '
    (.specialist_spawns | length) == 3
    # architect counted exactly once, exact, with per-spawn tokens
    and ([.specialist_spawns[] | select(.role.value == "architect")] | length) == 1
    and (.specialist_spawns[] | select(.role.value == "architect") | .role.confidence) == "exact"
    and (.specialist_spawns[] | select(.role.value == "architect") | .tokens != null)
    # challenger + systemsmith recovered as inferred, no per-spawn tokens
    and (.specialist_spawns[] | select(.role.value == "challenger") | .role.confidence) == "inferred"
    and (.specialist_spawns[] | select(.role.value == "systemsmith") | .role.confidence) == "inferred"
    and (.specialist_spawns[] | select(.role.value == "challenger") | (.tokens == null))
    and (._specialist_spawns_note | test("challenger-1") and test("systemsmith-1"))
    and (._specialist_spawns_note | test("architect-1") | not)
  ' "$RP3/accounting.json" > /dev/null || { echo "partial-emit recovery wrong (double-count or missing inferred)"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: delete the STEP A1-FALLBACK block in account-run.sh and (a)+(b) regress —
  # specialist_spawns becomes [] for the token-only log, so the length==3 assertion fails
  # and this fixture goes RED. Separately, re-gating the fallback behind
  # `gate_spawn_event_count -eq 0` regresses (d) — the partial-emit token-only specialists
  # are stranded and specialist_spawns drops to 1 (architect only).
expected: exit 0; stdout "PASS"; token-only log → 3 inferred specialist_spawns (note names attempt_ids), aggregate processed_total recovered; SPAWN-EVENT-present log → 1 exact spawn, no fallback; partial-emit log → 1 exact + 2 inferred, architect not double-counted, no close-out warning
phase: bug-fix · build-tail-tooling-fixes
owner: Bug 2 / account-run.sh STEP A1-FALLBACK (SPAWN-TOKEN-EVENT work-shape recovery)
