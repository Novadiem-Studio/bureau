name: grill-eval-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  EVAL="$ROOT/docs/evaluation/grill-checkpoint-eval.md"
  INDEX="$ROOT/docs/evaluation/index.md"
  IDEA="$ROOT/ideas/agent-framework/34-grilling-decision-checkpoint.md"

  [ -f "$EVAL" ] || { echo "FAIL: grill eval doc missing"; exit 1; }
  grep -q 'grill-checkpoint-eval.md' "$INDEX" \
    || { echo "FAIL: evaluation index missing grill eval doc"; exit 1; }
  grep -q 'GRILL-TRIGGER' "$EVAL" \
    || { echo "FAIL: eval doc missing GRILL-TRIGGER"; exit 1; }
  grep -q 'CHECKPOINT-EVENT' "$EVAL" \
    || { echo "FAIL: eval doc missing CHECKPOINT-EVENT"; exit 1; }
  grep -q 'rework_ratio' "$EVAL" \
    || { echo "FAIL: eval doc missing rework_ratio"; exit 1; }
  grep -q 'design-model correction count' "$EVAL" \
    || { echo "FAIL: eval doc missing design-model correction metric"; exit 1; }
  grep -q 'human_wait_total_s' "$EVAL" \
    || { echo "FAIL: eval doc missing human wait metric"; exit 1; }
  grep -q 'net-positive' "$EVAL" \
    || { echo "FAIL: eval doc missing net-positive acceptance"; exit 1; }
  grep -q 'measurement pending' "$IDEA" \
    || { echo "FAIL: idea should remain measurement pending"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the eval document, metric names, net-positive rule,
  # or measurement-pending idea status makes this fixture fail.
expected: exit 0; stdout "PASS"; grill measurement is explicit and the idea remains pending until net-positive evidence exists.
phase: 01 · feature (Bundle 34)
owner: docs/evaluation/grill-checkpoint-eval.md + ideas/agent-framework/34-grilling-decision-checkpoint.md
