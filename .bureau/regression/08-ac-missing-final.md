name: ac-missing-final
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  
  **AC 1.** The only acceptance criterion.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This plan implements FR 1. No AC citation here.
  PLAN
  cat > "$TMP/prompts.md" <<'PROMPTS'
  Prompts here. No AC citation in this file either.
  PROMPTS
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase final 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'ac-coverage' || { echo "FAIL: output does not name ac-coverage"; exit 1; }
  echo "$OUT" | grep -qF 'AC 1' || { echo "FAIL: output does not name AC 1"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes ac-coverage and names AC 1 as uncited
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
