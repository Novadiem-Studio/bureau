name: C4 — convention-source-resolve § heading extraction (present→clean, absent→fires)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF="$(mktemp -d)"
  trap 'rm -rf "$TMPF"' EXIT
  mkdir -p "$TMPF/repo"
  cat >"$TMPF/repo/CLAUDE.md" <<'CLAUDEEOF'
  ## Store slice conventions
  All store slices follow the naming pattern.
  CLAUDEEOF
  # ── Case A: correct citation, heading present → must emit NO convention-source-missing ──
  RUNDIR_A="$TMPF/run_a"
  mkdir -p "$RUNDIR_A"
  printf '{"target_repo": "%s"}' "$TMPF/repo" >"$RUNDIR_A/state.json"
  cat >"$RUNDIR_A/spec.md" <<'SPECEOF'
  ## Architecture
  The `authStore` store slice named per CLAUDE.md § Store slice conventions.
  SPECEOF
  touch "$RUNDIR_A/plan.md"
  out_a="$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUNDIR_A" --phase round1 2>&1)"
  rc_a=$?
  echo "CaseA: exit=$rc_a out=[$out_a]"
  if echo "$out_a" | grep -q 'convention-source-missing'; then
    echo "FAIL CaseA: correct citation with present heading triggered convention-source-missing (§ byte-offset bug?)"
    rm -rf "$TMPF"; exit 1
  fi
  [ "$rc_a" -eq 0 ] || { echo "FAIL CaseA: expected exit 0, got $rc_a"; rm -rf "$TMPF"; exit 1; }
  # ── Case B: absent heading → must emit convention-source-missing ──
  RUNDIR_B="$TMPF/run_b"
  mkdir -p "$RUNDIR_B"
  printf '{"target_repo": "%s"}' "$TMPF/repo" >"$RUNDIR_B/state.json"
  cat >"$RUNDIR_B/spec.md" <<'SPECEOF'
  ## Architecture
  The `authStore` store slice named per CLAUDE.md § Nonexistent Heading.
  SPECEOF
  touch "$RUNDIR_B/plan.md"
  out_b="$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUNDIR_B" --phase round1 2>&1)"
  rc_b=$?
  echo "CaseB: exit=$rc_b out=[$out_b]"
  echo "$out_b" | grep -q 'convention-source-missing' || { echo "FAIL CaseB: absent heading did not trigger convention-source-missing"; rm -rf "$TMPF"; exit 1; }
  [ "$rc_b" -eq 1 ] || { echo "FAIL CaseB: expected exit 1, got $rc_b"; rm -rf "$TMPF"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  CaseA: present heading resolves clean (no convention-source-missing, exit 0)
  CaseB: absent heading fires convention-source-missing (exit 1)
phase: Prompt 3 · feature (20260708-semantic-producer-checks)
owner: check_convention_citations § heading extraction — retire only if Check h on-disk resolve is removed
