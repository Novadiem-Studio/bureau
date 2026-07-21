name: grilling-trigger-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GRILL="$ROOT/docs/conventions/grilling.md"
  ANALYST="$ROOT/agents/analyst.md"
  FEATURE="$ROOT/workflows/feature.md"
  ROUTER="$ROOT/docs/conventions.md"

  [ -f "$GRILL" ] || { echo "FAIL: grilling convention missing"; exit 1; }
  grep -q 'docs/conventions/grilling.md' "$ROUTER" \
    || { echo "FAIL: conventions router does not point at grilling"; exit 1; }
  grep -q 'docs/conventions/grilling.md' "$ANALYST" \
    || { echo "FAIL: Analyst does not load grilling convention"; exit 1; }
  grep -q 'GRILL-TRIGGER:' "$ANALYST" \
    || { echo "FAIL: Analyst missing GRILL-TRIGGER line"; exit 1; }
  grep -q 'GRILL CHECKPOINT REQUEST' "$ANALYST" \
    || { echo "FAIL: Analyst missing checkpoint request block"; exit 1; }
  grep -q 'spec_exists_before' "$ANALYST" \
    || { echo "FAIL: Analyst trigger does not record spec_exists_before"; exit 1; }
  grep -q 'write no `spec.md`' "$ANALYST" \
    || { echo "FAIL: Analyst qualifying path does not forbid spec write"; exit 1; }
  grep -q 'Resolved grill decisions:' "$ANALYST" \
    || { echo "FAIL: Analyst missing resolved grill re-spawn contract"; exit 1; }
  grep -q 'any `spec.md` artifact exists' "$FEATURE" \
    || { echo "FAIL: feature workflow missing pre-spec ordering"; exit 1; }
  grep -q 'CHECKPOINT-EVENT' "$FEATURE" \
    || { echo "FAIL: feature workflow missing CHECKPOINT-EVENT"; exit 1; }
  grep -q 'id `"grill"`' "$FEATURE" \
    || { echo "FAIL: feature workflow missing grill checkpoint event id"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the trigger line, checkpoint request block, no-spec rule,
  # resolved-input path, or feature workflow event id makes this fixture fail.
expected: exit 0; stdout "PASS"; Analyst and feature workflow implement an auditable grill-first/no-spec-before-checkpoint contract.
phase: 01 · feature (Bundle 34)
owner: docs/conventions/grilling.md + agents/analyst.md + workflows/feature.md
