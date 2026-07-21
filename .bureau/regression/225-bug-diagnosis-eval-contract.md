name: bug-diagnosis-eval-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  EVAL="$ROOT/docs/evaluation/bug-diagnosis-eval.md"
  INDEX="$ROOT/docs/evaluation/index.md"
  IDEA="$ROOT/ideas/agent-framework/36-bug-diagnosis-discipline.md"
  BATTLE="$ROOT/workflows/battle-test/bug-diagnosis-discipline.md"

  [ -f "$EVAL" ] || { echo "FAIL: bug diagnosis eval doc missing"; exit 1; }
  [ -f "$BATTLE" ] || { echo "FAIL: bug diagnosis battle-test missing"; exit 1; }
  grep -qF 'bug-diagnosis-eval.md' "$INDEX" \
    || { echo "FAIL: evaluation index missing bug diagnosis eval doc"; exit 1; }
  grep -qF 'non_bureau_bug_fix_count' "$EVAL" \
    || { echo "FAIL: eval doc missing non-bureau metric"; exit 1; }
  grep -qF 'pre_fix_red_evidence_count' "$EVAL" \
    || { echo "FAIL: eval doc missing pre-fix red metric"; exit 1; }
  grep -qF 'post_fix_green_evidence_count' "$EVAL" \
    || { echo "FAIL: eval doc missing post-fix green metric"; exit 1; }
  grep -qF 'guess_patch_escape_count' "$EVAL" \
    || { echo "FAIL: eval doc missing guess-patch metric"; exit 1; }
  grep -qF 'measurement pending' "$IDEA" \
    || { echo "FAIL: idea should remain measurement pending"; exit 1; }
  grep -qF '5/5 cases pass' "$BATTLE" \
    || { echo "FAIL: battle-test run result missing"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the eval doc, metric names, measurement-pending idea
  # status, or battle-test run result makes this fixture fail.
expected: exit 0; stdout "PASS"; bug-diagnosis measurement is explicit and remains pending until non-bureau red/green evidence exists.
phase: 01 · feature (Bundle 36)
owner: docs/evaluation/bug-diagnosis-eval.md + ideas/agent-framework/36-bug-diagnosis-discipline.md
