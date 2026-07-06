name: no-prompts-final
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  # No prompts.md — absence at final is a defect
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase final 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'prompts.md' || { echo "FAIL: output does not name prompts.md"; exit 1; }
  echo "$OUT" | grep -qF 'presence' || { echo "FAIL: output does not name presence check"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script exits 1 naming prompts.md as absent
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
