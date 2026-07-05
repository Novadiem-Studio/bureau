name: account-run W2 — a mid-pipeline jq failure leaves no intermediate dotfile in RUN_DIR
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  D=$(mktemp -d)
  mkdir -p "$D/scripts"
  # Run a co-located COPY of the real account-run.sh next to a STUB token-consumer whose
  # spawn_tokens[challenger-1].tokens is a bare number (500). That makes the §9.5 enrich
  # step's `with_entries` crash MID-PIPELINE — leaking ${tmp_out}.enrich into RUN_DIR under
  # the pre-fix trap. account-run.sh's degrade-and-emit design continues and still publishes
  # accounting.json (schema 2, spawn un-enriched). The EXIT cleanup must sweep the leaked
  # dotfile without deleting the published accounting.json or any unrelated file.
  cp "$ROOT/scripts/account-run.sh" "$D/scripts/account-run.sh"
  printf '%s\n' '{"tokens":{"processed_total":{"value":700,"confidence":"exact"}},"conductor_tokens":{"confidence":"exact"},"wall_clock":{"active_spawn_time_s":{"value":60,"confidence":"exact"}},"checkpoints":{"entries":[]},"spawn_tokens":{"challenger-1":{"at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z","duration_s":{"value":60,"confidence":"exact"},"turns":3,"tokens":500,"rework":false}}}' > "$D/tok.json"
  printf '%s\n' '#!/bin/sh' "cat '$D/tok.json'" > "$D/scripts/account-tokens.sh"
  chmod +x "$D/scripts/account-tokens.sh"
  RP="$D/run"; mkdir -p "$RP"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-1","status":"started","at":"2026-07-05T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-1","status":"complete","at":"2026-07-05T00:01:00Z","started_at":"2026-07-05T00:00:00Z"}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["challenger"],"phase_status":"complete","critic_loops":{"challenger":0}}' > "$RP/state.json"
  printf 'SENTINEL\n' > "$RP/keep.txt"
  bash "$D/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || { rm -rf "$D"; echo "account-run exited non-zero"; exit 1; }
  # accounting.json published (degrade-and-emit) and valid — NOT deleted by the sweep.
  jq empty "$RP/accounting.json" 2>/dev/null || { rm -rf "$D"; echo "accounting.json missing or invalid"; exit 1; }
  # Confirm the mid-pipeline failure actually happened: schema bumped to 2 (steps a+c ran)
  # but the spawn is NOT enriched (enrich step b crashed). Proves the leak path was
  # exercised, not silently skipped — so the cleanup is genuinely under test.
  jq -e '.schema_version == 2 and (.specialist_spawns[0] | has("rework") | not)' "$RP/accounting.json" >/dev/null || { rm -rf "$D"; echo "expected mid-pipeline enrich crash not observed"; exit 1; }
  # W2 core: no .tmp-family intermediate dotfile remains in RUN_DIR.
  leak=$(find "$RP" -maxdepth 1 -name '.accounting.json.tmp.*' | wc -l | tr -d ' ')
  [ "$leak" -eq 0 ] || { rm -rf "$D"; echo "leaked $leak intermediate dotfile(s)"; exit 1; }
  # Scope: an unrelated pre-existing sibling is untouched by the sweep.
  [ "$(cat "$RP/keep.txt")" = "SENTINEL" ] || { rm -rf "$D"; echo "sweep touched an unrelated file"; exit 1; }
  rm -rf "$D"
  echo "PASS"
  # Mutation: neutering the EXIT cleanup's `rm -f "${tmp_prefix}."*` sweep leaves
  # ${tmp_out}.enrich stranded in RUN_DIR → leak count 1 → this fixture fails.
expected: exit 0; stdout "PASS"; zero .accounting.json.tmp.* remnants after a mid-pipeline enrich crash; accounting.json still valid; unrelated sibling untouched
phase: 05 · feature
owner: Prompt 5 / account-run.sh §6.0 EXIT cleanup dotfile sweep (reviewed W2)
