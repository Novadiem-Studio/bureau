name: prose-crossref-ok
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  SPEC
  # plan.md contains only a prose phrase — no space-form ID token
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1. See the EC about malformed JSON for more details.
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
  script exits 0 with stdout: preflight: clean (prose refs not flagged)
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
