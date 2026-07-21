name: seam-declaration-missing
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — Prompt seam discipline**
  Build prompts declare the tested seam.

  **AC 1.** Final preflight flags a checkpoint that lacks a seam declaration.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  cat > "$TMP/prompts.md" <<'PROMPTS'
  # Scoped Prompts

  ## Prompt 1 — Add behavior

  ```markdown
  Implement AC 1.

  ## Checkpoint
  npm test
  ```
  PROMPTS
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" --phase final 2>&1)"
  EC=$?
  echo "$OUT"
  echo "exit:$EC"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'seam-declaration-missing' || { echo "FAIL: output does not name seam-declaration-missing"; exit 1; }
  echo "$OUT" | grep -qF 'prompts.md' || { echo "FAIL: output does not name prompts.md"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output includes seam-declaration-missing for prompts.md and exit:1
phase: 01 · feature (Bundle 32)
owner: scripts/preflight-artifacts.sh check_seam_declarations

