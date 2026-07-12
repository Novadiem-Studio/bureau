name: #28 · agents/delegate.md verifying mode declares gate-failure as an ESCALATE (not a degrade-to-routine) AND carries escalation-signal 10 with the over-escalation carve-out
command: |
  # Prose-persona presence guard (same style as the delegate/watcher prose fixtures,
  # e.g. 27/49): a prose persona can't be behavior-tested cheaply, so pin the two
  # load-bearing instructions #28 added so a later edit can't silently drop them.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DM="$ROOT/agents/delegate.md"
  [ -f "$DM" ] || { echo "FAIL: agents/delegate.md missing"; exit 1; }

  # (1) The verifying-mode gate-failure escalate instruction is present.
  grep -q 'Gate-failure is an escalate, not a degrade' "$DM" \
    || { echo "FAIL: verifying-mode 'Gate-failure is an escalate, not a degrade' instruction missing"; exit 1; }
  # It must name BOTH failure shapes: a non-zero gate exit AND an absent results file.
  grep -q 'non-zero exit from .integration-gate.sh' "$DM" \
    || { echo "FAIL: gate-failure instruction does not name a non-zero integration-gate.sh exit"; exit 1; }
  grep -q 'absent .integration-results.json' "$DM" \
    || { echo "FAIL: gate-failure instruction does not name an absent integration-results.json"; exit 1; }

  # (2) Escalation-signal 10 is present in the Escalation signals list.
  grep -qE '^10\. The integration gate for this checkpoint failed to produce evidence' "$DM" \
    || { echo "FAIL: escalation signal 10 (integration-gate failed to produce evidence) missing"; exit 1; }
  # And the over-escalation carve-out (a present results file with an ordinary red
  # gate is NOT a gate failure) must accompany signal 10.
  grep -q 'Do not escalate on a \*present\* results file carrying an ordinary red gate' "$DM" \
    || { echo "FAIL: signal 10 over-escalation carve-out (present results file / ordinary red gate) missing"; exit 1; }

  echo "PASS"
  # Mutation note: deleting the "Gate-failure is an escalate, not a degrade"
  # paragraph OR the "10. The integration gate ... failed to produce evidence"
  # signal line from agents/delegate.md makes the corresponding grep fail.
expected: exit 0; stdout "PASS"; agents/delegate.md verifying mode contains the "Gate-failure is an escalate, not a degrade" instruction naming both a non-zero integration-gate.sh exit and an absent integration-results.json, AND escalation-signal 10 with its over-escalation carve-out. Mutation-test: removing either the instruction paragraph or signal 10 fails the guard.
phase: 03 · execute-plan (Delegate v2) — audit follow-up #28
owner: agents/delegate.md gate-failure escalate contract (audit #28)
