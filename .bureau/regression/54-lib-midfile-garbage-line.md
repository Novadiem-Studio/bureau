name: sum_transcript_usage — mid-file garbage line skipped, valid lines before and after still summed, exit 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    'GARBAGE_NOT_JSON_AT_ALL' \
    '{"type":"assistant","message":{"id":"msg-B","usage":{"input_tokens":50,"cache_creation_input_tokens":80,"cache_read_input_tokens":120,"output_tokens":5},"content":[{"type":"tool_use"}]}}' \
    > "$TMPF/t.jsonl"
  result=$(bash -c "source \"$ROOT/scripts/lib/bureau-token-lib.sh\"; sum_transcript_usage \"$TMPF/t.jsonl\"")
  rc=$?
  rm -rf "$TMPF"
  # Check exit 0 and correct sums (msg-A 100 + msg-B 50 = 150 input)
  [ "$rc" = "0" ] || exit 1
  echo "$result" | jq -e '.input == 150 and .processed == 850 and .turns == 2' > /dev/null || exit 1
  echo "PASS"
expected: exit 0; stdout "PASS" (input=150, processed=850, turns=2; garbage line silently skipped, msg-A and msg-B both counted)
phase: 01 · feature
owner: Prompt 1 fix (W1) / bureau-token-lib.sh sum_transcript_usage
