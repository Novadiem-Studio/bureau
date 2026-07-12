name: append-reviewer-tokens — a STRING .usage numeric field (e.g. "input_tokens":"1234") is coerced to 0 INLINE, the good sibling fields (cache_creation, cache_read, output) survive, processed is derived from the coerced components, and a _note names the coerced field — NOT the all-zero "not parseable JSON" fallback that discards the good siblings (B15/minor); an all-numeric envelope stays byte-identical with no _note
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  fail() { echo "FAIL: $*"; exit 1; }

  # ── FRAMING ───────────────────────────────────────────────────────────────────
  # The minor, reproduced-and-inverted: append-reviewer-tokens.sh read the four .usage
  # numeric fields with `// 0`, which does NOT coerce a STRING field (`//` only
  # substitutes on null/false/empty). A string "input_tokens":"1234" passed through
  # unchanged, reached the `$in+$cc+$cr` add, threw "string and number cannot be
  # added", the whole per-envelope jq failed, EVENT_LINE went empty, and the line-116
  # fallback emitted an ALL-ZERO event with the WRONG note ("not parseable JSON" — but
  # the envelope WAS parseable), discarding the good sibling fields. The fix reads each
  # field with `numbers // 0`: a string field coerces to 0 INLINE, the add never
  # crashes, the siblings survive, and a _note names the coerced field.

  RP="$TMPF/20260712-reviewer-string-field"; mkdir -p "$RP"; : > "$RP/log.md"

  # Envelope: input_tokens is the STRING "1234"; the other three are valid numbers.
  ENV='{"usage":{"input_tokens":"1234","cache_creation_input_tokens":100,"cache_read_input_tokens":200,"output_tokens":50},"num_turns":3}'
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RP" 05 "05-1" "$ENV" 2>/dev/null
  rc=$?; [ "$rc" = "0" ] || fail "append-reviewer-tokens exited $rc"

  LINE=$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed 's/^REVIEWER-TOKEN-EVENT: //')
  [ -n "$LINE" ] || fail "no REVIEWER-TOKEN-EVENT appended"

  # ── Assertion: string field coerced to 0, GOOD SIBLINGS PRESERVED ──────────────
  printf '%s' "$LINE" | jq -e '
    .tokens.input == 0
    and .tokens.cache_creation == 100
    and .tokens.cache_read == 200
    and .tokens.output == 50
    and .tokens.processed == 300
    and ((._note // "") | test("coerced to zero") and test("input_tokens"))
    and ((._note // "") | test("not parseable JSON") | not)
  ' >/dev/null \
    || fail "the string field was not coerced-with-siblings-preserved (or fell to the all-zero fallback): $(printf '%s' "$LINE" | jq -c '{tokens,note:._note}')"

  # ── Negative half: an all-numeric envelope stays byte-identical (no _note) ─────
  : > "$RP/log.md"
  ENV2='{"usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25,"output_tokens":10},"num_turns":2}'
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RP" 05 "05-1" "$ENV2" 2>/dev/null
  NEW=$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed 's/^REVIEWER-TOKEN-EVENT: //' | jq -cS 'del(.at)')
  : > "$RP/log.md"
  # The pre-fix (main) helper on the SAME all-numeric envelope — must be byte-identical
  # (the fix is a strict no-op on clean input). Run main's copy with the current lib.
  git show main:scripts/append-reviewer-tokens.sh > "$TMPF/mainscript.sh"
  mkdir -p "$TMPF/old/lib"; cp "$TMPF/mainscript.sh" "$TMPF/old/append-reviewer-tokens.sh"
  cp "$ROOT/scripts/lib/bureau-token-lib.sh" "$TMPF/old/lib/"
  chmod +x "$TMPF/old/append-reviewer-tokens.sh"
  bash "$TMPF/old/append-reviewer-tokens.sh" "$RP" 05 "05-1" "$ENV2" 2>/dev/null
  OLD=$(grep '^REVIEWER-TOKEN-EVENT:' "$RP/log.md" | sed 's/^REVIEWER-TOKEN-EVENT: //' | jq -cS 'del(.at)')
  [ "$OLD" = "$NEW" ] || fail "an all-numeric envelope is NOT byte-identical to pre-fix: old=$OLD new=$NEW"
  printf '%s' "$NEW" | jq -e 'has("_note") | not' >/dev/null || fail "an all-numeric envelope carries a spurious _note: $NEW"

  echo "PASS"
  # Mutation note (the minor, inverted): in a scratch copy of scripts/append-reviewer-
  # tokens.sh, revert the four `numbers // 0` back to `// 0`. Then the string
  # input_tokens is NOT coerced, the `$in+$cc+$cr` add throws "string and number cannot
  # be added", the per-envelope jq fails, EVENT_LINE goes empty, and the line-116
  # fallback emits the all-zero "not parseable JSON" event → cache_read == 0 (should be
  # 200), _note says "not parseable JSON" → the sibling-preserved assertion fails.
  # Restore → passes.
expected: exit 0; stdout "PASS"; a reviewer envelope whose .usage.input_tokens is the string "1234" produces a REVIEWER-TOKEN-EVENT with tokens.input == 0 (coerced inline), cache_creation/cache_read/output preserved (100/200/50), processed == 300 (derived), and a _note naming the coerced field — NOT the all-zero "not parseable JSON" fallback; an all-numeric envelope is byte-identical to the pre-fix helper with no _note. Mutation-test: reverting numbers // 0 back to // 0 crashes the add and collapses the envelope to the all-zero fallback.
phase: 04 · feature — B15 minor (reviewer string-field coerce-inline)
owner: append-reviewer-tokens.sh numbers // 0 usage-field coercion + coerced-field _note (B15)
