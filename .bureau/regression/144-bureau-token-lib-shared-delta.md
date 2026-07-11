name: bureau-token-lib shared delta — compute_delta_line clamp + processed-identity + clamp-note (AC-10, extracted arithmetic)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # Source the library (BASH_SOURCE guard requires it be sourced, not executed).
  # shellcheck disable=SC1091
  . "$ROOT/scripts/lib/bureau-token-lib.sh"

  # --- Case 1: clean delta, no clamp, processed == input+cc+cr identity ---
  usage='{"input":30000000,"cache_creation":12000000,"cache_read":10000000,"processed":52000000,"output":400000,"turns":10}'
  baseline='{"session_id":"sess-A","input":20000000,"cache_creation":8000000,"cache_read":6000000,"processed":34000000,"output":300000,"turns":5}'
  line=$(compute_delta_line "$usage" "sess-A" "2026-01-01T00:00:00Z" "true" \
    20000000 8000000 6000000 300000 5 "$baseline")
  echo "$line" | jq -e '
    .session_id == "sess-A" and .final == true and
    .tokens.input == 10000000 and
    .tokens.cache_creation == 4000000 and
    .tokens.cache_read == 4000000 and
    .tokens.processed == 18000000 and
    (.tokens.processed == (.tokens.input + .tokens.cache_creation + .tokens.cache_read)) and
    .tokens.output == 100000 and
    .turns == 5 and
    (.baseline.processed == 34000000) and
    (has("_note") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case 2: a field below baseline clamps to 0, processed re-derived from
  #     the CLAMPED components, and a _note names the clamped field ---
  usage2='{"input":5,"cache_creation":200,"cache_read":300,"processed":505,"output":10,"turns":1}'
  baseline2='{"session_id":"sess-B","input":100,"cache_creation":80,"cache_read":120,"processed":300,"output":5,"turns":0}'
  line2=$(compute_delta_line "$usage2" "sess-B" "2026-01-01T00:00:00Z" "false" \
    100 80 120 5 0 "$baseline2")
  # input raw = 5-100 = -95 → clamp 0; cache_creation 200-80=120; cache_read 300-120=180
  # processed = 0+120+180 = 300 (re-derived from clamped, NOT 505-300)
  echo "$line2" | jq -e '
    .tokens.input == 0 and
    .tokens.cache_creation == 120 and
    .tokens.cache_read == 180 and
    .tokens.processed == 300 and
    (.tokens.processed == (.tokens.input + .tokens.cache_creation + .tokens.cache_read)) and
    (._note | test("clamped input"))
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  # --- Case 3: compute_legacy_line emits the 6-key shape, no baseline, no _note ---
  line3=$(compute_legacy_line "$usage" "sess-C" "2026-01-01T00:00:00Z" "true")
  echo "$line3" | jq -e '
    .session_id == "sess-C" and .final == true and
    .tokens.processed == 52000000 and
    (has("baseline") | not) and (has("_note") | not)
  ' > /dev/null || { rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation note: change the clamp `if $raw_input < 0 then 0` to `else $raw_input`
  # (drop the clamp) → Case 2 processed becomes 205 (505-300) with negative input
  # → the identity + clamped-input assertions fail. This guards the extracted
  # arithmetic that both emitters now share.
expected: exit 0; stdout "PASS"; compute_delta_line clamps per-field, re-derives processed from clamped components (identity holds), names clamped fields in _note; compute_legacy_line emits the bare 6-key shape
phase: 02 · feature
owner: bureau-token-lib.sh shared compute_delta_line / compute_legacy_line (v2-conductor-capture)
