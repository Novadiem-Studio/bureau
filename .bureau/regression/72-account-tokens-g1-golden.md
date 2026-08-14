name: account-tokens G1 golden — all seven derived metrics use the explicit post-hoc fragment (AC 13/14/15)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/g1"
  mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T00:01:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T00:01:30Z","started_at":"2026-07-05T00:01:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":2,"attempt_id":"architect-2","status":"started","at":"2026-07-05T00:01:30Z","rework":true}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":2,"attempt_id":"architect-2","status":"complete","at":"2026-07-05T00:02:00Z","started_at":"2026-07-05T00:01:30Z"}' \
    'CHECKPOINT-EVENT: {"id":"design-model","status":"raised","at":"2026-07-05T00:02:00Z"}' \
    'CHECKPOINT-EVENT: {"id":"design-model","status":"resolved","at":"2026-07-05T00:04:00Z","decision":"proceed as designed"}' \
    'CHECKPOINT-EVENT: {"id":"fixture-review","status":"raised","at":"2026-07-05T00:04:00Z"}' \
    'CHECKPOINT-EVENT: {"id":"fixture-review","status":"resolved","at":"2026-07-05T00:07:00Z","decision":"fixtures approved"}' \
    > "$RP/log.md"
  printf '%s\n' '{"critic_loops": {"architect": 1, "challenger": 1}}' > "$RP/state.json"
  jq -n '{
    delegate:{tokens:{input:0,cache_creation:0,cache_read:0,processed:0,output:0},confidence:"exact"},
    conductor:{tokens:{input:40,cache_creation:60,cache_read:100,processed:200,output:10},confidence:"exact"},
    specialists:[
      {attempt_id:"architect-1",confidence:"exact",tokens:{input:200,cache_creation:300,cache_read:500,processed:1000,output:50}},
      {attempt_id:"challenger-1",confidence:"exact",tokens:{input:100,cache_creation:150,cache_read:250,processed:500,output:30}},
      {attempt_id:"architect-2",confidence:"exact",tokens:{input:60,cache_creation:90,cache_read:150,processed:300,output:15}}
    ]
  }' > "$RP/posthoc.json"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" "$RP/posthoc.json") || { rm -rf "$TMPF"; exit 1; }
  # All seven derived values, all confidence "exact" (final:true present, every
  # spawn matched, every duration/checkpoint parses). Hand-derivable:
  #   processed_total = 1000+500+300+200 = 2000
  #   rework_ratio    = 300/2000 = 0.15   (only architect-2 is rework:true)
  #   tokens_per_loop = 2000/2 = 1000
  #   active_spawn_time_s = 60+30+30 = 120
  #   minutes_per_loop = 120/60/2 = 1.0
  #   human_wait_total_s = 120+180 = 300
  #   active_vs_blocked_ratio = 120/300 = 0.4
  echo "$out" | jq -e '
    .tokens.processed_total.value == 2000 and
    .tokens.processed_total.confidence == "exact" and
    .tokens.rework_ratio.value == 0.15 and
    .tokens.rework_ratio.confidence == "exact" and
    .tokens.tokens_per_loop.value == 1000 and
    .tokens.tokens_per_loop.confidence == "exact" and
    .wall_clock.active_spawn_time_s.value == 120 and
    .wall_clock.active_spawn_time_s.confidence == "exact" and
    .wall_clock.minutes_per_loop.value == 1.0 and
    .checkpoints.human_wait_total_s.value == 300 and
    .checkpoints.human_wait_total_s.confidence == "exact" and
    .checkpoints.active_vs_blocked_ratio.value == 0.4 and
    .checkpoints.active_vs_blocked_ratio.confidence == "exact" and
    .conductor_tokens.confidence == "unavailable" and
    .tokens.output_total.confidence == "estimated"
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: ignore optional arg 2 or swap rework:true to an attempt-counter
  # heuristic and processed_total/rework_ratio shift off 2000/0.15.
expected: exit 0; stdout "PASS"; explicit post-hoc arg 2 yields processed_total=2000(exact), rework_ratio=0.15, tokens_per_loop=1000, output estimated; narrative SPAWN/CHECKPOINT derivations remain exact and the per-leg conductor placeholder remains unavailable until account-run merges the fragment
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh golden fixture G1
