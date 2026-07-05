name: account-run AC6 — spawn heading + non-empty phases_complete but zero SPAWN-EVENT lines fires the enforcement gate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/ac6"
  mkdir -p "$RP"
  # A narrative "Spawned" heading and a non-empty phases_complete, but ZERO
  # structured SPAWN-EVENT: lines — the close-out-without-records signature (EC 8).
  printf '%s\n' \
    '## [2026-07-05T00:00:00Z] — Spawned The Architect (architect) -> started' \
    'Some prose about the run but no SPAWN-EVENT: lines.' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"feature","phases_complete":["architect"],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RP/state.json"
  out=$(bash "$ROOT/scripts/account-run.sh" "$RP" 2>/dev/null) || { rm -rf "$TMPF"; exit 1; }
  # stdout carries the warning AND accounting.json carries the durable marker.
  printf '%s' "$out" | grep -qF '[CLOSE-OUT WARNING]' || { rm -rf "$TMPF"; exit 1; }
  jq -e '._close_out_warning == "true"' "$RP/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: remove the STEP A1 gate and neither the stdout warning nor the
  # _close_out_warning marker appears — both checks fail.
expected: exit 0; stdout contains "[CLOSE-OUT WARNING]"; accounting.json._close_out_warning == "true"
phase: 05 · feature
owner: Prompt 5 / account-run.sh enforcement gate (AC 6)
