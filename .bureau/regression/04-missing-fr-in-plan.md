name: missing-fr-in-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 5 — Test requirement**
  A test requirement that must be cited by ID in plan.md.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  ## Phase 1
  Implementation details that never cite the FR by ID.
  Mentions the requirement in prose only.
  PLAN
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'fr-coverage' || { echo "FAIL: output does not name fr-coverage"; exit 1; }
  echo "$OUT" | grep -qF 'FR 5' || { echo "FAIL: output does not name FR 5"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes fr-coverage and FR 5
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
