name: account-run AC5 — legacy 7-key run with no Bundle 11 lines stays schema_version 1, new blocks absent
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac5"
  mkdir -p "$RP"
  # Old-format 7-key SPAWN-EVENT lines only — no at/started_at/rework, no
  # SPAWN-TOKEN-EVENT / CONDUCTOR-TOKEN-EVENT / CHECKPOINT-EVENT. account-tokens.sh
  # returns the all-empty fragment → treated as "no token data" → merge skipped →
  # today's schema unchanged with schema_version 1.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started"}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"complete"}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["analyst"],"phase_status":"complete","critic_loops":{"analyst":0}}' > "$RP/state.json"
  out=$(bash "$ROOT/scripts/account-run.sh" "$RP" 2>/dev/null) || { rm -rf "$TMPF"; exit 1; }
  # exits 0, valid JSON, schema_version 1, none of the four new blocks present, and
  # the legacy specialist_spawns entry carries only its original six keys (no rework
  # / at / tokens enrichment).
  jq -e '
    .schema_version == 1 and
    (has("tokens") | not) and
    (has("conductor_tokens") | not) and
    (has("wall_clock") | not) and
    (has("checkpoints") | not) and
    (.specialist_spawns[0] | has("rework") | not) and
    (.specialist_spawns[0] | has("tokens") | not)
  ' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: if the merge ran unconditionally (bumping schema to 2 or adding blocks
  # on a no-token-data run), the schema_version / has-block checks fail.
expected: exit 0; stdout "PASS"; schema_version=1, no tokens/conductor_tokens/wall_clock/checkpoints blocks, specialist_spawns entry un-enriched
phase: 05 · feature
owner: Prompt 5 / account-run.sh Bundle 11 backward compat (AC 5)
