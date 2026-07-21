name: build-diff-two-axis-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SLICE="$ROOT/agents/critic/build-diff.md"
  [ -f "$SLICE" ] || { echo "FAIL: build-diff slice missing"; exit 1; }

  grep -q '^### Spec-fidelity axis' "$SLICE" \
    || { echo "FAIL: Spec-fidelity axis heading missing"; exit 1; }
  grep -q '^### Standards axis' "$SLICE" \
    || { echo "FAIL: Standards axis heading missing"; exit 1; }
  grep -q '^### Reporting contract' "$SLICE" \
    || { echo "FAIL: Reporting contract heading missing"; exit 1; }
  grep -q '^### Spec-fidelity$' "$SLICE" \
    || { echo "FAIL: report template missing Spec-fidelity heading"; exit 1; }
  grep -q '^### Standards$' "$SLICE" \
    || { echo "FAIL: report template missing Standards heading"; exit 1; }
  grep -q '^### Axis summary$' "$SLICE" \
    || { echo "FAIL: report template missing Axis summary heading"; exit 1; }
  grep -q 'single cross-axis winner' "$SLICE" \
    || { echo "FAIL: no-reranking rule missing"; exit 1; }
  grep -q 'Axis membership is a review-output contract' "$SLICE" \
    || { echo "FAIL: record-schema no-axis-fields decision missing"; exit 1; }
  echo "PASS"
  # Mutation note: deleting either axis heading, the Axis summary template, the
  # no-reranking sentence, or the no-axis-fields schema decision makes this fixture fail.
expected: exit 0; stdout "PASS"; build-diff slice carries Spec-fidelity and Standards axes, the output template, the no-cross-axis-reranking rule, and the no-axis-fields verdict-record decision.
phase: 01 · feature (Bundle 33)
owner: agents/critic/build-diff.md two-axis output contract
