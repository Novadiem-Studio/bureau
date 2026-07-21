name: seam-declaration-none-clean
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Prompt seam discipline**
  Build prompts declare the tested seam.

  **AC 1.** An explicit no-seam declaration is accepted.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  cat > "$TMP/prompts.md" <<'PROMPTS'
  # Scoped Prompts

  ## Prompt 1 — Documentation-only sync

  ```markdown
  Implement AC 1.

  ## Checkpoint
  Seams under test: none — documentation-only prompt.
  rg -n "Prompt seam discipline" docs agents scripts
  ```
  PROMPTS
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase final 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 0 ] || { echo "FAIL: expected exit 0, got $EC"; exit 1; }
  echo "$OUT" | grep -qx 'preflight: clean' || { echo "FAIL: expected clean preflight"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout includes preflight: clean and ends with PASS
phase: 01 · feature (Bundle 32)
owner: scripts/preflight-artifacts.sh check_seam_declarations

