name: missing-spec
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/plan.md" <<'PLAN'
  ## Phase 1
  Implementation content.
  PLAN
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'spec.md' || { echo "FAIL: output does not mention spec.md"; exit 1; }
  echo "$OUT" | grep -qF 'presence' || { echo "FAIL: output does not name presence check"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
