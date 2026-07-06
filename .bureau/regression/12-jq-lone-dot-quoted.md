name: jq-lone-dot-quoted
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  # spec.md contains a fenced block with the single-quoted lone-dot jq gate:
  # jq -e '.' — a quoted lone dot is never a legitimate filter and must be caught.
  # Mutation note: reverting the regex widening (removing the single-quoted-pattern
  # grep check from check_snippets in preflight-artifacts.sh) makes this fixture
  # go red — the script exits 0 instead of 1, failing the [ "$EC" -eq 1 ] assertion.
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  
  ```
  jq -e '.' input.json
  ```
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'jq-lone-dot' || { echo "FAIL: output does not name jq-lone-dot"; exit 1; }
  echo "$OUT" | grep -qF 'spec.md' || { echo "FAIL: output does not name spec.md"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes jq-lone-dot and names spec.md with approx line number
  mutation note: reverting the regex widening makes this fixture go red (exit 1 from fixture itself)
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
