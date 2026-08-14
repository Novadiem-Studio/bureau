name: account-tokens timestamp-integrity guard — fabricated narrative SPAWN-EVENT times (round hours, wrong date) that disagree with the unfakeable hook SPAWN-TOKEN-EVENT times are refused an "exact" active_spawn_time_s badge (downgraded to "suspect" with a _note naming the tell)
retired: 07 · execute-plan — FR4 REPLACE retired this live-rail token-rollup assertion; post-hoc aggregation is the sole per-leg source
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ts-wash"
  mkdir -p "$RP"
  # Reproduction of the 20260709-liquid-glass-nav exact-wash. The NARRATIVE
  # SPAWN-EVENT times (Conductor/LLM-written) are tidy round hours 00:00:00Z →
  # 07:00:00Z on 07-09, implying a 25200s (7h) active span. But the HOOK-emitted
  # SPAWN-TOKEN-EVENT `at` (subagent-stop.sh runs `date -u` — unfakeable) reads the
  # REAL clock: 07-10 at 06:25, minutes of real work, a DIFFERENT calendar date.
  # Before the guard, account-tokens.sh summed the narrative durations and stamped
  # active_spawn_time_s.confidence "exact" — a fabricated 7h wearing an exact badge.
  # After the guard, the per-attempt hook cross-check (narrative terminal `at` vs
  # same-attempt_id hook `at`) sees a different calendar date, so the narrative
  # times are treated as fabricated: confidence downgrades to "suspect" (NOT
  # "exact"), with a mandatory _note naming the tell.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-09T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-09T07:00:00Z","started_at":"2026-07-09T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-m1","at":"2026-07-10T06:25:11Z","turns":2,"tokens":{"input":10,"cache_creation":20,"cache_read":30,"processed":500,"output":40}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"sess-001","at":"2026-07-10T06:30:00Z","turns":42,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":10},"final":true}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["mage"],"phase_status":"complete","critic_loops":{"mage":1}}' > "$RP/state.json"
  # Drive account-run.sh end-to-end (mirror fixture 129) so the guarded confidence
  # lands in accounting.json's merged wall_clock block, at schema_version 2.
  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  # Load-bearing assertions: the run merged to schema 2 (the fabrication is NOT an
  # error — it must still account cleanly), and active_spawn_time_s.confidence is
  # NOT "exact". It is "suspect", and the _note names the specific tell.
  jq -e '
    .schema_version == 2 and
    (.wall_clock.active_spawn_time_s.confidence != "exact") and
    (.wall_clock.active_spawn_time_s.confidence == "suspect") and
    (.wall_clock.active_spawn_time_s._note | test("hook SPAWN-TOKEN-EVENT")) and
    (.wall_clock.active_spawn_time_s._note | test("different calendar date")) and
    (.wall_clock.active_spawn_time_s._note | test("fabricated"))
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: delete the `elif $ts_fabricated then "suspect"` arm of the $active_conf
  # ladder in scripts/account-tokens.sh (revert to the bare `if $active_all_exact
  # then "exact" else "partial" end`) and the confidence reads "exact" on this
  # fabricated-time log → both the `!= "exact"` and `== "suspect"` assertions fail.
expected: exit 0; stdout "PASS"; schema_version=2, wall_clock.active_spawn_time_s.confidence="suspect" (NOT "exact"), _note names the hook-cross-check tell (different calendar date / fabricated)
phase: 04 · feature
owner: timestamp-exact-wash-guard / account-tokens.sh timestamp-integrity check
