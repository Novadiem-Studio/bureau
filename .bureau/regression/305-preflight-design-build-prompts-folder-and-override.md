name: preflight auto-discovers design-build's fixed RUN_DIR/prompts/ folder with no recorded state, and --prompts-dir explicitly overrides resolution
phase: bug-fix · retainscore-run11-framework-defects (2026-09-23)
owner: scripts/preflight-artifacts.sh — prompts-artifact resolution
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

  # --- Case C: design-build's prompt folder is a FIXED path under RUN_DIR
  # (workflows/design-build.md: RUN_DIR/prompts/), unlike execute-plan's
  # variable beside-the-plan-doc location — it needs no state.json field.
  RUN_C="$TMPD/run-c"
  mkdir -p "$RUN_C/prompts"
  cat > "$RUN_C/state.json" <<'EOF'
  {"workflow":"design-build","phase":"final","target_repo":"/dev/null"}
  EOF
  cat > "$RUN_C/plan.md" <<'EOF'
  ## Phase 1
  Build the screen.
  EOF
  cat > "$RUN_C/prompts/00-index.md" <<'EOF'
  # Job — design-build · execution prompts
  ## How to run
  ## Steps
  **01** — The Mage · web: screen
  ## Non-negotiable gotchas
  EOF
  cat > "$RUN_C/prompts/01-screen.md" <<'EOF'
  # 01 — web: screen
  Coder: The Mage
  Execution-profile: role-default
  Plan: ../plan.md §1
  Reviewability: web only
  ## Do
  1. Build the screen.
  ## Checkpoint (green before 02)
  Seams under test: renders screen
  - vitest passes
  EOF

  out_c=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_C" --phase final 2>&1); rc_c=$?
  [ "$rc_c" -eq 0 ] || { echo "FAIL C: design-build run with RUN_DIR/prompts/ should pass --phase final: $out_c"; exit 1; }

  # --- Case D: --prompts-dir explicitly overrides resolution to an arbitrary
  # folder, regardless of workflow or state.json.
  RUN_D="$TMPD/run-d"
  mkdir -p "$RUN_D"
  EXPLICIT="$TMPD/explicit-prompts"
  mkdir -p "$EXPLICIT"
  cp "$RUN_C/prompts/00-index.md" "$EXPLICIT/"
  cp "$RUN_C/prompts/01-screen.md" "$EXPLICIT/"
  cat > "$RUN_D/state.json" <<'EOF'
  {"workflow":"execute-plan","phase":"final","target_repo":"/dev/null"}
  EOF
  cat > "$RUN_D/spec.md" <<'EOF'
  ## Requirements
  **AC 1** something
  EOF
  cat > "$RUN_D/plan.md" <<'EOF'
  ## Phase 1
  Implements AC 1.
  EOF

  out_d=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_D" --phase final --prompts-dir "$EXPLICIT" 2>&1); rc_d=$?
  [ "$rc_d" -eq 0 ] || { echo "FAIL D: --prompts-dir override should resolve cleanly: $out_d"; exit 1; }

  # Sanity: without the override, run D (no prompts.md, no prompt_folder field)
  # still fails — the flag is additive, not a workflow-wide bypass.
  out_d2=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_D" --phase final 2>&1); rc_d2=$?
  [ "$rc_d2" -eq 1 ] || { echo "FAIL D2: run D without the override must still fail: $out_d2"; exit 1; }

  echo PASS
expected: exit 0; stdout PASS. Mutation: delete the "elif [ -d "$RUN_DIR/prompts" ]" branch from the prompts-artifact resolution block and case C wrongly fails with the prompts.md presence defect; delete the "-n "$PROMPTS_DIR_FLAG"" branch (or the --prompts-dir arg-parse case) and case D wrongly fails the same way.
