name: emit-event-spawn-event-seven-keys-valid-at-field (AC-12/13)
phase: 04 · enforcement-relocation (FR 7)
owner: scripts/emit-event.sh — spawn-event type, all seven required keys + shell-computed at
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # Case A (AC-12): full invocation — all seven required fields present
  out=$(bash "$ROOT/scripts/emit-event.sh" spawn-event \
    --role analyst --agent "Analizer 2000" \
    --configured-model sonnet --actual-model sonnet \
    --attempt 1 --attempt-id analyst-1 --status started 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: emit-event.sh exited $rc (expect 0) for full invocation"; exit 1; }

  # stdout is one line starting with "SPAWN-EVENT: "
  line_count=$(printf '%s\n' "$out" | grep -c .)
  [ "$line_count" -eq 1 ] || { echo "FAIL: stdout has $line_count lines (expect 1)"; exit 1; }
  printf '%s\n' "$out" | grep -q '^SPAWN-EVENT: ' \
    || { echo "FAIL: stdout does not start with 'SPAWN-EVENT: ' (got: $out)"; exit 1; }

  # JSON payload parses as object
  payload=$(printf '%s\n' "$out" | sed 's/^SPAWN-EVENT: //')
  printf '%s\n' "$payload" | jq -e 'type == "object"' >/dev/null \
    || { echo "FAIL: JSON payload does not parse as object"; exit 1; }

  # All seven keys present
  for key in role agent configured_model actual_model attempt attempt_id status; do
    printf '%s\n' "$payload" | jq -e "has(\"$key\")" >/dev/null \
      || { echo "FAIL: key '$key' missing from payload"; exit 1; }
  done

  # "at" field matches ISO-8601 UTC pattern
  at_val=$(printf '%s\n' "$payload" | jq -r '.at // ""')
  printf '%s\n' "$at_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
    || { echo "FAIL: at field '$at_val' does not match ISO-8601 UTC pattern"; exit 1; }

  # No "nonce" field present (EC 11)
  printf '%s\n' "$payload" | jq -e 'has("nonce") | not' >/dev/null \
    || { echo "FAIL: payload has a 'nonce' field (EC 11 violation)"; exit 1; }

  # Case B (AC-13): missing required field — exit non-zero, stdout empty, stderr contains "missing field"
  out_b=$(bash "$ROOT/scripts/emit-event.sh" spawn-event \
    --role analyst --agent "Analizer 2000" \
    --attempt 1 --attempt-id analyst-1 --status started 2>"$TMPF/stderr.txt")
  rc_b=$?
  [ "$rc_b" -ne 0 ] || { echo "FAIL: emit-event.sh exited 0 when required fields missing (expect non-zero)"; exit 1; }

  # stdout must be EMPTY (no SPAWN-EVENT line emitted)
  [ -z "$out_b" ] || { echo "FAIL: stdout is not empty when required fields missing (got: $out_b)"; exit 1; }

  # stderr contains "missing field"
  grep -q "missing field" "$TMPF/stderr.txt" \
    || { echo "FAIL: stderr does not contain 'missing field' (got: $(cat "$TMPF/stderr.txt"))"; exit 1; }

  # Case C: non-numeric --attempt — exit non-zero AND stdout empty (blocker fix)
  out_c=$(bash "$ROOT/scripts/emit-event.sh" spawn-event \
    --role analyst --agent "Analizer 2000" \
    --configured-model sonnet --actual-model sonnet \
    --attempt abc --attempt-id analyst-1 --status started 2>"$TMPF/stderr_c.txt")
  rc_c=$?
  [ "$rc_c" -ne 0 ] || { echo "FAIL: emit-event.sh exited 0 for non-numeric --attempt (expect non-zero)"; exit 1; }

  # stdout must be EMPTY — no torn SPAWN-EVENT prefix line
  [ -z "$out_c" ] || { echo "FAIL: stdout is not empty for non-numeric --attempt (got: $out_c)"; exit 1; }

  echo "PASS"
  # Mutation note: remove the [ -n "$configured_model" ] || missing "configured_model"
  # guard from emit-event.sh. Then the missing-field invocation in Case B succeeds (exit 0)
  # and emits a SPAWN-EVENT line with a blank configured_model value. Case B rc_b assertion
  # fails (was non-zero, now 0) and the empty-stdout assertion fails.
  # Mutation note (Case C): remove the validate_numeric "--attempt" call from emit-event.sh.
  # Then "abc" passes through to jq --argjson which fails, leaving $payload empty, but
  # without the guard_payload check the script would print "SPAWN-EVENT: " (torn line) and
  # exit 0 — the rc_c non-zero assertion and the empty-stdout assertion both fail.
