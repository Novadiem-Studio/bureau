name: adr-records-eval-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  EVAL="$ROOT/docs/evaluation/adr-records-eval.md"
  INDEX="$ROOT/docs/evaluation/index.md"
  IDEA="$ROOT/ideas/agent-framework/35-adr-decision-records.md"
  BATTLE="$ROOT/workflows/battle-test/adr-decision-records.md"

  [ -f "$EVAL" ] || { echo "FAIL: ADR eval doc missing"; exit 1; }
  [ -f "$BATTLE" ] || { echo "FAIL: ADR battle-test missing"; exit 1; }
  grep -q 'adr-records-eval.md' "$INDEX" \
    || { echo "FAIL: evaluation index missing ADR eval doc"; exit 1; }
  grep -q 'adr_created_count' "$EVAL" \
    || { echo "FAIL: eval doc missing adr_created_count"; exit 1; }
  grep -q 'adr_cited_later_count' "$EVAL" \
    || { echo "FAIL: eval doc missing later citation metric"; exit 1; }
  grep -q 'accepted_adr_contradiction_count' "$EVAL" \
    || { echo "FAIL: eval doc missing contradiction metric"; exit 1; }
  grep -q 'measurement pending' "$IDEA" \
    || { echo "FAIL: idea should remain measurement pending"; exit 1; }
  grep -q '5/5 cases pass' "$BATTLE" \
    || { echo "FAIL: battle-test run result missing"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the eval doc, metric names, measurement-pending idea
  # status, or battle-test run result makes this fixture fail.
expected: exit 0; stdout "PASS"; ADR usage measurement is explicit and the idea remains pending until cross-run mileage exists.
phase: 01 · feature (Bundle 35)
owner: docs/evaluation/adr-records-eval.md + ideas/agent-framework/35-adr-decision-records.md
