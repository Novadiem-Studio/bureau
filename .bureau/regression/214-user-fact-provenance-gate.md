name: user-fact-provenance-gate
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GRILL="$ROOT/docs/conventions/grilling.md"
  ANALYST="$ROOT/agents/analyst.md"
  CRITIC="$ROOT/agents/critic/spec-plan.md"

  for term in timezone 'locale or language' currency jurisdiction recipients schedule environment 'external service'; do
    grep -q "$term" "$GRILL" \
      || { echo "FAIL: grilling user-fact list missing $term"; exit 1; }
  done
  grep -q 'ASSUMED default:' "$GRILL" \
    || { echo "FAIL: grilling convention missing ASSUMED default rule"; exit 1; }
  grep -q 'User-fact sourcing requirement' "$ANALYST" \
    || { echo "FAIL: Analyst missing user-fact sourcing requirement"; exit 1; }
  grep -q 'source: resolved grill' "$ANALYST" \
    || { echo "FAIL: Analyst does not cite resolved grill answers"; exit 1; }
  grep -q 'User-fact provenance gate' "$CRITIC" \
    || { echo "FAIL: Critic missing user-fact provenance gate"; exit 1; }
  grep -q 'ASSUMED default:' "$CRITIC" \
    || { echo "FAIL: Critic gate missing ASSUMED default allowance"; exit 1; }
  grep -q 'bare user fact is a \*\*Warning\*\*' "$CRITIC" \
    || { echo "FAIL: Critic gate missing bare user fact severity"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the user-fact list, ASSUMED default allowance,
  # Analyst sourcing rule, or Critic provenance gate makes this fixture fail.
expected: exit 0; stdout "PASS"; user facts must carry source or ASSUMED default provenance, and the spec-plan Critic checks the rule.
phase: 01 · feature (Bundle 34)
owner: docs/conventions/grilling.md + agents/analyst.md + agents/critic/spec-plan.md
