name: diagnosing-bugs-loadable-contract
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  CONVENTION="$ROOT/docs/conventions/diagnosing-bugs.md"
  ROUTER="$ROOT/docs/conventions.md"
  CHECK="$ROOT/check-framework.sh"
  ANALYST="$ROOT/agents/analyst.md"
  BUGFIX="$ROOT/workflows/bug-fix.md"

  [ -f "$CONVENTION" ] || { echo "FAIL: diagnosing-bugs convention missing"; exit 1; }
  grep -qF 'docs/conventions/diagnosing-bugs.md' "$ROUTER" \
    || { echo "FAIL: convention router missing diagnosing-bugs module"; exit 1; }
  grep -qF 'diagnosing-bugs' "$CHECK" \
    || { echo "FAIL: check-framework does not track diagnosing-bugs convention module"; exit 1; }
  grep -qF '## Tight Loop First' "$CONVENTION" \
    || { echo "FAIL: tight-loop section missing"; exit 1; }
  grep -qF '## Minimise Before Theory' "$CONVENTION" \
    || { echo "FAIL: minimise section missing"; exit 1; }
  grep -qF '## Hypothesise And Instrument When Foggy' "$CONVENTION" \
    || { echo "FAIL: foggy hypothesis/instrument section missing"; exit 1; }
  grep -qF '## Regression Test Home Rule' "$CONVENTION" \
    || { echo "FAIL: regression home rule missing"; exit 1; }
  grep -qF 'Regression test: none — no correct seam' "$CONVENTION" \
    || { echo "FAIL: no-correct-seam escape missing"; exit 1; }
  grep -qF 'ANALYST REPRODUCE COMPLETE' "$ANALYST" \
    || { echo "FAIL: Analyst reproduce mode missing"; exit 1; }
  grep -qF 'docs/conventions/diagnosing-bugs.md' "$BUGFIX" \
    || { echo "FAIL: bug-fix workflow does not load diagnosing-bugs"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the convention, router/check-framework pointer, tight loop,
  # minimise/foggy loop, regression home rule, no-correct-seam escape, Analyst reproduce
  # mode, or bug-fix workflow pointer makes this fixture fail.
expected: exit 0; stdout "PASS"; diagnosing-bugs is a loadable convention wired into bug-fix reproduce mode.
phase: 01 · feature (Bundle 36)
owner: docs/conventions/diagnosing-bugs.md + workflows/bug-fix.md + agents/analyst.md
