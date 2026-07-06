name: clean-run
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — First requirement**
  A simple requirement.
  
  **FR 2 — Second requirement**
  Another requirement.
  
  **AC 1.** First acceptance criterion.
  
  **AC 2.** Second acceptance criterion.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  ## Phase 1
  
  This plan implements FR 1 and FR 2.
  
  Satisfies: AC 1, AC 2.
  PLAN
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 0 ] || { echo "FAIL: expected exit 0, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'preflight: clean' || { echo "FAIL: stdout is not 'preflight: clean'"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script exits 0 with stdout: preflight: clean (AC 5)
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
