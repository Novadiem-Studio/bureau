name: derived token metrics degrade honestly when the post-hoc fragment is absent
owner: scripts/account-tokens.sh optional arg-2 seam after FR4 REPLACE
phase: 05 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RUN_PATH="$TMPF/run"
  mkdir -p "$RUN_PATH"
  printf '%s\n' '{"critic_loops":{"architect":2}}' > "$RUN_PATH/state.json"
  : > "$RUN_PATH/log.md"
  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN_PATH") || exit 1
  printf '%s' "$out" | jq -e '
    .tokens.processed_total.value == 0
    and .tokens.processed_total.confidence == "unavailable"
    and (.tokens.processed_total._note | test("no post-hoc aggregator fragment"))
    and .tokens.rework_ratio.value == null
    and .tokens.rework_ratio.confidence == "unavailable"
    and (.tokens.rework_ratio._note | length > 0)
    and .tokens.tokens_per_loop.value == null
    and .tokens.tokens_per_loop.confidence == "unavailable"
    and (.tokens.tokens_per_loop._note | test("no post-hoc aggregator fragment"))
    and .tokens.output_total.value == 0
    and .tokens.output_total.confidence == "unavailable"
    and (.tokens.output_total._note | test("no post-hoc aggregator fragment"))
    and .tokens.unattributed_records == []
  ' >/dev/null || { echo "FAIL: missing-fragment degradation was silent or exact"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; absent arg 2 yields unavailable noted derived metrics, null-safe ratios, and no note-free exact zero
