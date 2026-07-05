name: sum_transcript_usage — truncated final line skipped, valid lines summed, exit 0
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # Write two full valid lines (same msg-A, one group) then a truncated line (no closing brace)
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":300,"output_tokens":10},"content":[{"type":"text"}]}}' \
    > "$TMPF/t.jsonl"
  printf '{"type":"assistant","message":{"id":"msg-B","usage":{"input_tokens":50' >> "$TMPF/t.jsonl"
  # Source lib and call function; capture result for machine check
  result=$(bash -c "source \"$ROOT/scripts/lib/bureau-token-lib.sh\"; sum_transcript_usage \"$TMPF/t.jsonl\"")
  rc=$?
  [ "$rc" = "0" ] || { rm -rf "$TMPF"; exit 1; }
  # Machine check: .input must equal 100 (only msg-A counted; truncated msg-B silently skipped)
  echo "$result" | jq -e '.input == 100' > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS" (input=100; deduped msg-A counts once; truncated msg-B line silently skipped)
phase: 01 · feature
owner: Prompt 1 fix (W1) / bureau-token-lib.sh sum_transcript_usage
