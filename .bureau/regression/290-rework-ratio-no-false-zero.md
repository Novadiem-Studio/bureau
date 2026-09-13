name: rework_ratio reports undeterminable (not 0.0) when an orphan terminal lost the rework flag; a non-zero critic_loops count alone does NOT trigger it
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)

  # Shared setup: one properly paired architect spawn, never flagged rework.
  # The post-hoc fragment supplies a non-zero processed_total so the rework_ratio
  # branch is actually reached (processed_total 0 short-circuits earlier, by
  # design). delegate-state.json is required: the fragment validator only accepts
  # conductor confidence "exact" when legs matches the recorded conductor ids.
  # Every tokens block must also satisfy processed == input + cache_creation +
  # cache_read, or the whole fragment is rejected and processed_total falls to 0.
  mk_run() {
    rd="$1"; loops="$2"
    mkdir -p "$rd"
    printf '%s\n' \
      'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-09-10T06:00:00Z"}' \
      'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-09-10T06:30:00Z"}' \
      > "$rd/log.md"
    printf '%s\n' "{\"accounting\":{\"status\":\"complete\"},\"critic_loops\":$loops}" > "$rd/state.json"
    printf '%s\n' '{"delegate_session_id":"del-1","conductor_agent_id":"cond-1","conductor_agent_ids":["cond-1"]}' > "$rd/delegate-state.json"
    jq -n '{
      delegate:{tokens:{input:0,cache_creation:0,cache_read:0,processed:0,output:0},turns:0,confidence:"exact"},
      conductor:{tokens:{input:10,cache_creation:10,cache_read:20,processed:40,output:5},turns:1,legs:1,confidence:"exact"},
      specialists:[
        {attempt_id:"architect-1",role:"architect",agent_id:"arch-a",confidence:"exact",turns:1,tokens:{input:200,cache_creation:300,cache_read:500,processed:1000,output:50}}
      ]
    }' > "$rd/posthoc.json"
  }
  ratio() { bash "$ROOT/scripts/account-tokens.sh" "$1" "$1/posthoc.json" 2>/dev/null | jq -c '.tokens.rework_ratio'; }

  # Case A — a NON-ZERO critic_loops count with no orphan and no flag must keep
  # the honest 0.0. A Challenger round can be adjudicated "note + proceed"
  # (workflows/execute-plan.md step 2) without ever re-spawning the producer, so
  # loops are entirely consistent with zero rework. This is the contract fixture
  # 80 pins, and an earlier version of this fix broke it by treating critic_loops
  # as evidence of a missing flag.
  A="$TMPF/a"; mk_run "$A" '{"analyst":0,"architect":1,"prompts":1}'
  ra=$(ratio "$A")
  printf '%s' "$ra" | jq -e '.value == 0.0 and .confidence != "unavailable"' >/dev/null \
    || { echo "FAIL: case A (loops, no orphan) should stay 0.0, got $ra"; rm -rf "$TMPF"; exit 1; }

  # Case B — an orphan terminal. The rework flag lives on the started line only,
  # so a dropped start takes the flag with it and the numerator is unknowable.
  B="$TMPF/b"; mk_run "$B" '{"analyst":0,"architect":0,"prompts":0}'
  printf 'SPAWN-EVENT: %s\n' '{"role":"systemsmith","agent":"The Systemsmith","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"systemsmith-c2-2","status":"complete","at":"2026-09-10T07:00:00Z"}' >> "$B/log.md"
  jq '.specialists += [{attempt_id:"systemsmith-c2-2",role:"systemsmith",agent_id:"ss-b",confidence:"exact",turns:1,tokens:{input:100,cache_creation:150,cache_read:250,processed:500,output:0}}]' \
    "$B/posthoc.json" > "$B/ph.tmp" && mv "$B/ph.tmp" "$B/posthoc.json"
  rb=$(ratio "$B")
  printf '%s' "$rb" | jq -e '.value == null and .confidence == "unavailable"' >/dev/null \
    || { echo "FAIL: case B should be null/unavailable, got $rb"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$rb" | jq -e '._note | test("systemsmith-c2-2")' >/dev/null \
    || { echo "FAIL: case B note should name the orphan, got $rb"; rm -rf "$TMPF"; exit 1; }

  # Case C — the honest zero MUST survive. No loops, no orphans, no rework:
  # 0.0 is the truth and must not be swept into "undeterminable".
  C="$TMPF/c"; mk_run "$C" '{"analyst":0,"architect":0,"prompts":0}'
  rc=$(ratio "$C")
  printf '%s' "$rc" | jq -e '.value == 0.0 and .confidence != "unavailable"' >/dev/null \
    || { echo "FAIL: case C should stay 0.0 and not be unavailable, got $rc"; rm -rf "$TMPF"; exit 1; }

  # Case D — a genuinely flagged rework still computes a real ratio.
  # processed_total = 1000 + 250 + 40 (conductor) = 1290; rework = 250.
  D="$TMPF/d"; mk_run "$D" '{"analyst":0,"architect":1,"prompts":0}'
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":2,"attempt_id":"architect-2","status":"started","at":"2026-09-10T07:00:00Z","rework":true}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":2,"attempt_id":"architect-2","status":"complete","at":"2026-09-10T07:30:00Z"}' \
    >> "$D/log.md"
  jq '.specialists += [{attempt_id:"architect-2",role:"architect",agent_id:"arch-b",confidence:"exact",turns:1,tokens:{input:50,cache_creation:75,cache_read:125,processed:250,output:0}}]' \
    "$D/posthoc.json" > "$D/ph.tmp" && mv "$D/ph.tmp" "$D/posthoc.json"
  rd_=$(ratio "$D")
  printf '%s' "$rd_" | jq -e '.value != null and .value > 0 and .confidence != "unavailable"' >/dev/null \
    || { echo "FAIL: case D should compute a real non-zero ratio, got $rd_"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$rd_" | jq -e '(.value * 10000 | round) == (250 / 1290 * 10000 | round)' >/dev/null \
    || { echo "FAIL: case D ratio should be 250/1290, got $rd_"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". Case B (orphan terminal, no rework flag) yields value null / confidence "unavailable" with a note naming the orphan. Case A (critic_loops > 0 but no orphan) and case C (nothing at all) both keep the honest 0.0 — critic_loops is NOT evidence of a lost flag, because a Challenger round can end "note + proceed" without re-spawning the producer (the contract fixture 80 pins). Case D (a real flagged rework) still computes 250/1290. Mutation: restore `elif ($rework_ids | length) == 0 then {value:0.0,confidence:$pt_conf}` as the second branch of the rework_ratio expression in scripts/account-tokens.sh → case B reports 0.0 and its first assertion fails.
phase: eval follow-up — 2026-09-12 eight-run eval
owner: docs/evaluation/framework-evaluation-log.md § 2026-09-12 eight-run eval (open lever 2, rework_ratio); issue #28
