name: fowler-smell-floor-loadable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  BASE="$ROOT/docs/conventions/fowler-smell-baseline.md"
  ROUTER="$ROOT/docs/conventions.md"
  SLICE="$ROOT/agents/critic/build-diff.md"
  [ -f "$BASE" ] || { echo "FAIL: Fowler smell baseline missing"; exit 1; }

  grep -q 'docs/conventions/fowler-smell-baseline.md' "$ROUTER" \
    || { echo "FAIL: conventions router does not point at Fowler smell baseline"; exit 1; }
  grep -q 'docs/conventions/fowler-smell-baseline.md' "$SLICE" \
    || { echo "FAIL: build-diff slice does not load Fowler smell baseline"; exit 1; }

  for smell in \
    "Mysterious Name" "Duplicated Code" "Feature Envy" "Data Clumps" \
    "Primitive Obsession" "Repeated Switches" "Shotgun Surgery" \
    "Divergent Change" "Speculative Generality" "Message Chains" \
    "Middle Man" "Refused Bequest"
  do
    grep -q "$smell" "$BASE" || { echo "FAIL: missing smell: $smell"; exit 1; }
  done

  count=$(grep -c '^[0-9][0-9]*\. \*\*' "$BASE")
  [ "$count" -eq 12 ] || { echo "FAIL: expected 12 smell entries, got $count"; exit 1; }
  echo "PASS"
  # Mutation note: deleting the router/slice pointer or any smell name makes this fixture fail.
expected: exit 0; stdout "PASS"; Fowler smell baseline is loadable through the router and build-diff slice and contains exactly the 12 named floor smells.
phase: 01 · feature (Bundle 33)
owner: docs/conventions/fowler-smell-baseline.md + agents/critic/build-diff.md

