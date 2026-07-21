name: adr-records-loadable-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  CONVENTION="$ROOT/docs/conventions/adr-records.md"
  ROUTER="$ROOT/docs/conventions.md"
  TEMPLATE="$ROOT/templates/adr.md"
  ANALYST="$ROOT/agents/analyst.md"
  ARCHITECT="$ROOT/agents/architect.md"
  CRITIC="$ROOT/agents/critic.md"
  RECONCILE="$ROOT/workflows/docs-reconcile.md"
  CHECK="$ROOT/check-framework.sh"

  [ -f "$CONVENTION" ] || { echo "FAIL: ADR convention missing"; exit 1; }
  [ -f "$TEMPLATE" ] || { echo "FAIL: ADR template missing"; exit 1; }
  grep -q 'docs/conventions/adr-records.md' "$ROUTER" \
    || { echo "FAIL: convention router missing ADR module"; exit 1; }
  grep -q 'adr-records' "$CHECK" \
    || { echo "FAIL: check-framework does not track ADR convention module"; exit 1; }
  grep -q 'Create an ADR only when all three are true' "$CONVENTION" \
    || { echo "FAIL: ADR qualification rule missing"; exit 1; }
  grep -q 'Accepted target-repo ADRs are allowed durable project ground truth' "$CRITIC" \
    || { echo "FAIL: Challenger coldness carve-in missing"; exit 1; }
  grep -q 'Do not write ADRs' "$ANALYST" \
    || { echo "FAIL: Analyst write prohibition missing"; exit 1; }
  grep -q 'ADR records:' "$ARCHITECT" \
    || { echo "FAIL: Architect handoff missing ADR records field"; exit 1; }
  grep -q 'superseding ADR' "$RECONCILE" \
    || { echo "FAIL: docs-reconcile missing supersession rule"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the convention, router pointer, template, Analyst no-write
  # rule, Architect handoff field, Critic coldness wording, or docs-reconcile
  # supersession rule makes this fixture fail.
expected: exit 0; stdout "PASS"; ADR records are a loadable convention with role-specific read/write/reconcile contracts.
phase: 01 · feature (Bundle 35)
owner: docs/conventions/adr-records.md + agents/*.md + workflows/docs-reconcile.md
