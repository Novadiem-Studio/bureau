name: FR 10 run-2 delta — account-tokens.sh on run-2 log.md alone reports 18M exact, not 52M (AC 1)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # Run 2 setup: delta log.md with baseline-tagged lines; two lines same session_id
  # intermediate (10M) and final (18M); take-max picks 18M (higher processed).
  RUN2="$TMPF/run2"
  mkdir -p "$RUN2"
  echo '{"accounting":{"status":"complete"}}' > "$RUN2/state.json"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"c66e9679","at":"2026-07-06T10:00:00Z","turns":135,"tokens":{"input":6000000,"cache_creation":2000000,"cache_read":2000000,"processed":10000000,"output":100000},"final":false,"baseline":{"session_id":"c66e9679","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":121}}' > "$RUN2/log.md"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"c66e9679","at":"2026-07-06T12:00:00Z","turns":137,"tokens":{"input":10000000,"cache_creation":4000000,"cache_read":4000000,"processed":18000000,"output":200000},"final":true,"baseline":{"session_id":"c66e9679","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":121}}' >> "$RUN2/log.md"
  r2=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN2" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$r2" | jq -e '.conductor_tokens.tokens.processed == 18000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$r2" | jq -e '.conductor_tokens.confidence == "exact"' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$r2" | jq -e '.conductor_tokens.legs == 1' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$r2" | jq -e '.conductor_tokens.tokens.processed != 52000000' >/dev/null \
    || { rm -rf "$TMPF"; exit 1; }
  # Sum assertion: run-1 log.md (no baseline, same session_id, cumulative 34M, final:true)
  RUN1="$TMPF/run1"
  mkdir -p "$RUN1"
  echo '{"accounting":{"status":"complete"}}' > "$RUN1/state.json"
  printf 'CONDUCTOR-TOKEN-EVENT: %s\n' '{"session_id":"c66e9679","at":"2026-07-06T08:00:00Z","turns":121,"tokens":{"input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000},"final":true}' > "$RUN1/log.md"
  r1=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN1" 2>/dev/null)
  [ $? -eq 0 ] || { rm -rf "$TMPF"; exit 1; }
  run1_processed=$(printf '%s' "$r1" | jq '.conductor_tokens.tokens.processed')
  [ "$(( 18000000 + run1_processed ))" = "52000000" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS"; run-2 log.md alone: conductor_tokens.tokens.processed==18000000, confidence=="exact", legs==1, value!=52000000; run-1 log.md alone: processed==34000000; sum 18M+34M==52M. Mutation: change both run-2 event lines to tokens.processed==52000000 (raw cumulative, no baseline subtraction) → take-max picks 52000000 → assertion 4 (!=52000000) fails.
phase: 07 · feature (execute build tail)
owner: prompts.md § Prompt 7 — Fixture G, FR 10 run-2 delta (AC 1, FR 10)
