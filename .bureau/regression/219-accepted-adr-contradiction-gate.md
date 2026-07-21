name: accepted-adr-contradiction-gate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SLICE="$ROOT/agents/critic/spec-plan.md"
  CRITIC="$ROOT/agents/critic.md"
  CONTRACT="$ROOT/docs/conventions/agent-contracts.md"

  grep -q 'Accepted-ADR contradiction gate' "$SLICE" \
    || { echo "FAIL: spec-plan slice missing accepted-ADR gate"; exit 1; }
  grep -q 'Status:` is `accepted`' "$SLICE" \
    || { echo "FAIL: accepted status trigger missing"; exit 1; }
  grep -q 'Status: superseded-by-NNNN' "$SLICE" \
    || { echo "FAIL: supersession escape missing"; exit 1; }
  grep -q 'Blocker' "$SLICE" \
    || { echo "FAIL: gate is not a Blocker"; exit 1; }
  grep -q 'criteria, and accepted target-repo `docs/adr/`' "$CRITIC" \
    || { echo "FAIL: Critic input contract missing ADR read"; exit 1; }
  grep -q 'criteria, and accepted target-repo `docs/adr/`' "$CONTRACT" \
    || { echo "FAIL: agent-contracts Challenger instance missing ADR read"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the gate, accepted-status trigger, supersession escape,
  # Blocker severity, or synced input contract makes this fixture fail.
expected: exit 0; stdout "PASS"; cold spec-plan review blocks contradictions with accepted ADRs unless superseded.
phase: 01 · feature (Bundle 35)
owner: agents/critic/spec-plan.md + agents/critic.md + docs/conventions/agent-contracts.md
