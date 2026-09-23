name: preflight fails loudly when this run's secret nonce appears in log.md, stays clean otherwise, and ignores a foreign pointer file's nonce
phase: bug-fix · retainscore-run11-framework-defects (2026-09-23)
owner: scripts/preflight-artifacts.sh — nonce-exposure check (agents/orchestrator.md § Run-scope nonce lifecycle)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR"
  cat > "$RUN_DIR/state.json" <<'EOF'
  {"workflow":"feature","phase":"round1","target_repo":"/dev/null"}
  EOF
  cat > "$RUN_DIR/spec.md" <<'EOF'
  ## Requirements
  **AC 1** something
  EOF
  cat > "$RUN_DIR/plan.md" <<'EOF'
  ## Phase 1
  Implements AC 1.
  EOF

  POINTER="$TMPD/pointer.json"
  NONCE="a1b2c3d4-deadbeef-nonce-value"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-09-23T00:00:00Z","project_dir":"/tmp"}\n' "$RUN_DIR" "$NONCE" > "$POINTER"

  # Case E: clean log.md — must stay clean.
  cat > "$RUN_DIR/log.md" <<'EOF'
  ## [2026-09-23T00:00:00Z] — Run started
  EOF
  out_e=$(BUREAU_POINTER_FILE="$POINTER" bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_DIR" --phase round1 2>&1); rc_e=$?
  [ "$rc_e" -eq 0 ] || { echo "FAIL E: clean log.md should not trip the nonce check: $out_e"; exit 1; }

  # Case F: the nonce leaked into log.md, exactly as retainscore run 11's
  # Challenger spawns did (echoing it into their own review headers) — must
  # fail loudly and name the exact log.md line.
  cat > "$RUN_DIR/log.md" <<EOF
  ## [2026-09-23T00:00:00Z] — Run started
  Attempt: challenger-r1-2 · run nonce $NONCE · review_mode: verification
  EOF
  out_f=$(BUREAU_POINTER_FILE="$POINTER" bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_DIR" --phase round1 2>&1); rc_f=$?
  [ "$rc_f" -eq 1 ] || { echo "FAIL F: a leaked nonce in log.md must fail: $out_f"; exit 1; }
  printf '%s\n' "$out_f" | grep -qF "log.md:2 — nonce-exposure" \
    || { echo "FAIL F: expected a nonce-exposure defect naming log.md:2: $out_f"; exit 1; }

  # Case G: a pointer file for a DIFFERENT run_dir must never be treated as
  # this run's nonce, even if its value happens to appear in this log.md.
  FOREIGN_POINTER="$TMPD/foreign-pointer.json"
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-09-23T00:00:00Z","project_dir":"/tmp"}\n' "/some/other/run" "$NONCE" > "$FOREIGN_POINTER"
  out_g=$(BUREAU_POINTER_FILE="$FOREIGN_POINTER" bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_DIR" --phase round1 2>&1); rc_g=$?
  [ "$rc_g" -eq 0 ] || { echo "FAIL G: a foreign pointer's nonce must not be checked against this run's log.md: $out_g"; exit 1; }

  echo PASS
expected: exit 0; stdout PASS. Mutation: delete the check_nonce_exposure function/call and case F wrongly passes (exit 0) instead of failing on the leaked nonce; delete the ptr_run_dir/RUN_DIR match guard and case G wrongly fails on a foreign run's nonce.
