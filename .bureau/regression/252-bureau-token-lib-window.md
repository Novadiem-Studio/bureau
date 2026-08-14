name: bureau-token-lib sum_transcript_usage applies half-open optional windows without changing the omitted path
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  TRANSCRIPT="$TMPF/window.jsonl"
  OMITTED="$TMPF/omitted.jsonl"
  # shellcheck disable=SC1091
  . "$ROOT/scripts/lib/bureau-token-lib.sh"

  printf '%s\n' \
    '{"timestamp":"2026-08-13T00:00:00Z","type":"assistant","message":{"id":"before","usage":{"input_tokens":1},"content":[{"type":"text"}]}}' \
    '{"timestamp":"2026-08-13T00:00:01Z","type":"assistant","message":{"id":"lower","usage":{"input_tokens":2},"content":[{"type":"tool_use"}]}}' \
    '{"timestamp":"2026-08-13T00:00:02Z","type":"assistant","message":{"id":"inside","usage":{"cache_creation_input_tokens":3},"content":[{"type":"text"}]}}' \
    '{"timestamp":"2026-08-13T00:00:03Z","type":"assistant","message":{"id":"upper","usage":{"cache_read_input_tokens":5},"content":[{"type":"text"}]}}' \
    '{"timestamp":"2026-08-13T00:00:04Z","type":"assistant","message":{"id":"after","usage":{"output_tokens":7},"content":[{"type":"text"}]}}' \
    > "$TRANSCRIPT"

  windowed=$(sum_transcript_usage "$TRANSCRIPT" "2026-08-13T00:00:01Z" "2026-08-13T00:00:03Z") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$windowed" | jq -e '
    . == {input:2,cache_creation:3,cache_read:0,processed:5,output:0,turns:1}
  ' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  until_only=$(sum_transcript_usage "$TRANSCRIPT" "" "2026-08-13T00:00:03Z") || { rm -rf "$TMPF"; exit 1; }
  printf '%s' "$until_only" | jq -e '
    . == {input:3,cache_creation:3,cache_read:0,processed:6,output:0,turns:1}
  ' >/dev/null || { rm -rf "$TMPF"; exit 1; }

  # This is the exact pre-window return for a fixed transcript, including jq's
  # stable whitespace. The untimestamped assistant also pins that the omitted
  # path does not pass through a timestamp selector.
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"plain","usage":{"input_tokens":4,"cache_creation_input_tokens":6,"cache_read_input_tokens":8,"output_tokens":10},"content":[{"type":"tool_use"}]}}' \
    '{"type":"assistant","message":{"id":"plain","usage":{"input_tokens":4,"cache_creation_input_tokens":6,"cache_read_input_tokens":8,"output_tokens":10},"content":[{"type":"text"}]}}' \
    > "$OMITTED"
  omitted=$(sum_transcript_usage "$OMITTED") || { rm -rf "$TMPF"; exit 1; }
  expected='{
    "input": 4,
    "cache_creation": 6,
    "cache_read": 8,
    "processed": 18,
    "output": 10,
    "turns": 1
  }'
  [ "$omitted" = "$expected" ] || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutations: changing >= to > drops lower and fails windowed; requiring both
  # bounds admits upper into until_only; timestamp-filtering the omitted path
  # drops plain and fails the byte-exact golden.
expected: exit 0; stdout "PASS"; [since,until) is half-open, until-only filters independently, omitted args preserve the exact prior JSON
phase: 02 · execute-plan
owner: Prompt 02 / bureau-token-lib.sh optional window seam
