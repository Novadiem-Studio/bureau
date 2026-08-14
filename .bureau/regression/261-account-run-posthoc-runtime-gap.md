name: account-run post-hoc runtime-gap — Codex is honestly unavailable with no live-token fallback
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/20260813-runtime-gap"
  mkdir -p "$RP"
  printf '{"runtime":"openai"}\n' > "$RP/model-routing.json"
  jq -cn --arg target "$TMPF/target" '{target_repo:$target,workflow:"feature",phase_status:"complete",phases_complete:["analyst"],critic_loops:{analyst:2}}' > "$RP/state.json"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:01Z","rework":true}' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"gpt","actual_model":"gpt","attempt":1,"attempt_id":"analyst-1","status":"complete","at":"2026-08-13T00:00:02Z","started_at":"2026-08-13T00:00:01Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"analyst-1","agent_id":"live-specialist","at":"2026-08-13T00:00:02Z","turns":2,"tokens":{"input":20,"cache_creation":30,"cache_read":50,"processed":100,"output":10}}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"live-conductor","at":"2026-08-13T00:00:02Z","turns":3,"tokens":{"input":40,"cache_creation":60,"cache_read":100,"processed":200,"output":20},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"live-delegate","at":"2026-08-13T00:00:02Z","turns":4,"tokens":{"input":60,"cache_creation":90,"cache_read":150,"processed":300,"output":30},"final":true}' \
    > "$RP/log.md"

  gap=$(bash "$ROOT/scripts/aggregate-transcripts.sh" "$RP" --until "2026-08-13T00:01:00Z") || exit 1
  printf '%s' "$gap" | jq -e '._runtime_gap | contains("openai") and contains("no Claude JSONL")' >/dev/null || exit 1
  printf '%s' "$gap" > "$TMPF/gap.json"

  # The optional account-tokens arg rejects a runtime-gap fragment. FR4 REPLACE
  # has no live-token fallback, even when historical hook records remain in log.md.
  direct=$(bash "$ROOT/scripts/account-tokens.sh" "$RP" "$TMPF/gap.json") || exit 1
  printf '%s' "$direct" | jq -e '
    .tokens.processed_total.value == 0 and
    .tokens.processed_total.confidence == "unavailable" and
    (.tokens.processed_total._note | contains("no post-hoc aggregator fragment")) and
    .tokens.rework_ratio.value == null and
    .tokens.rework_ratio.confidence == "unavailable" and
    .tokens.tokens_per_loop.value == null and
    .tokens.tokens_per_loop.confidence == "unavailable" and
    .tokens.output_total.confidence == "unavailable" and
    .conductor_tokens.confidence == "unavailable" and
    .delegate_tokens.confidence == "unavailable"
  ' >/dev/null || exit 1

  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1 || exit 1
  jq -e '
    .schema_version == 2 and
    .conductor_tokens.tokens.processed == 0 and
    .conductor_tokens.confidence == "unavailable" and
    .delegate_tokens.tokens.processed == 0 and
    .delegate_tokens.confidence == "unavailable" and
    (.specialist_spawns[0] | has("tokens") | not) and
    .tokens.processed_total.value == 0 and
    .tokens.processed_total.confidence == "unavailable" and
    .tokens.rework_ratio.value == null and
    .tokens.tokens_per_loop.value == null and
    .tokens.output_total.confidence == "unavailable" and
    (has("_posthoc") | not)
  ' "$RP/accounting.json" >/dev/null || exit 1
  echo "PASS"
  # Mutation: restore a live-token fallback and the historical 200/300/100 hook
  # figures wash this named runtime gap into apparently usable accounting.
expected: exit 0; stdout "PASS"; runtime-gap CHANGE-family member (historical owner overlaps account-tokens): aggregate-transcripts names the openai/no-Claude-JSONL gap, account-tokens rejects the gated arg-2 fragment, and account-run emits unavailable zero-with-notes/no specialist tokens/no _posthoc instead of falling back to live Conductor=200, Delegate=300, specialist=100
phase: 04 · execute-plan
owner: Prompt 04 / account-run.sh + account-tokens.sh runtime-gap fallback parity
