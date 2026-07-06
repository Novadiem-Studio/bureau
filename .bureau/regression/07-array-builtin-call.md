name: array-builtin-call
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  # spec.md contains a fenced block with the Bash 4+ array-builtin pattern (exact literal from spec FR 5d)
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Only FR**
  A requirement.
  
  ```
  readarray -t lines < input.txt
  ```
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase round1 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'array-builtin-call' || { echo "FAIL: output does not name array-builtin-call"; exit 1; }
  echo "$OUT" | grep -qF 'spec.md' || { echo "FAIL: output does not name spec.md"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes array-builtin-call and names spec.md with approx line number
phase: 01 · feature (Bundle 12)
owner: scripts/preflight-artifacts.sh
