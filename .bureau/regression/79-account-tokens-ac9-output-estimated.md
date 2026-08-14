name: account-tokens AC 9 — fragment-fed output_total confidence is always "estimated"
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/r"
  mkdir -p "$RP"
  printf '%s\n' '{"critic_loops":{"mage":1}}' > "$RP/state.json"
  printf '%s\n' '{"delegate_session_id":"delegate-output","conductor_agent_id":"cond-output","conductor_agent_ids":["cond-output"]}' > "$RP/delegate-state.json"
  # A fully exact post-hoc fragment — output must STILL be "estimated", never
  # "exact" (large file writes bill as cache, not output).
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-05T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    > "$RP/log.md"
  jq -n '{
    delegate:{tokens:{input:0,cache_creation:0,cache_read:0,processed:0,output:0},turns:0,confidence:"exact"},
    conductor:{tokens:{input:20,cache_creation:30,cache_read:50,processed:100,output:10},turns:1,legs:1,confidence:"exact"},
    specialists:[{attempt_id:"mage-1",role:"mage",agent_id:"mage-a",confidence:"exact",turns:1,tokens:{input:100,cache_creation:150,cache_read:250,processed:500,output:40}}]
  }' > "$RP/posthoc.json"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" "$RP/posthoc.json") || { rm -rf "$TMPF"; exit 1; }
  echo "$out" | jq -e '
    .tokens.output_total.confidence == "estimated" and
    .tokens.output_total.value == 50 and
    .tokens.processed_total == (.tokens.processed_total | select(.value == 600 and .confidence == "exact"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: label output "exact" alongside processed_total and the assertion fails.
expected: exit 0; stdout "PASS"; explicit post-hoc arg 2 yields output_total={value:50,confidence:"estimated"} while processed_total={value:600,confidence:"exact"}
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh AC 9 output estimated
