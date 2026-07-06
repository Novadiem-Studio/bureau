name: dangling-ec-ref
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  
  **EC 1 — Only EC**
  One edge case.
  SPEC
  # plan.md contains a space-form reference to EC 99 (not defined in spec.md)
  # Written as two parts joined to keep the space-form token out of this fixture's own prose
  printf '%s\n' 'This implements FR 1. See also EC 99 for details.' > "$TMP/plan.md"
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'dangling-ref' || { echo "FAIL: output does not name dangling-ref"; exit 1; }
  echo "$OUT" | grep -qF 'plan.md' || { echo "FAIL: output does not name plan.md"; exit 1; }
  echo "$OUT" | grep -qF 'cross-artifact reference' || { echo "FAIL: output does not include opt-out hint"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes dangling-ref, names plan.md and the opt-out hint
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
