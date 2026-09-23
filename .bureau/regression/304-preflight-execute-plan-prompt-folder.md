name: preflight --phase final resolves an execute-plan prompt folder via state.json#prompt_folder instead of hardcoding RUN_DIR/prompts.md; a feature run with neither still fails
phase: bug-fix · retainscore-run11-framework-defects (2026-09-23)
owner: scripts/preflight-artifacts.sh — prompts-artifact resolution
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

  # --- Case A: execute-plan run. The prompt folder sits beside the plan doc in
  # the TARGET repo (workflows/execute-plan/prompt-folder-format.md), never at
  # RUN_DIR/prompts.md. Recorded via state.json#prompt_folder (relative to
  # target_repo). Must PASS --phase final with no prompts.md false-positive.
  TARGET="$TMPD/target-repo"
  mkdir -p "$TARGET/docs/plans/demo/11-search-demand-endpoints"
  cat > "$TARGET/docs/plans/demo/11-search-demand-endpoints/00-index.md" <<'EOF'
  # Job 11 — search-demand endpoints · execution prompts
  See ../11-search-demand-endpoints.md.
  ## How to run
  ## Steps
  **01** — The Systemsmith · api: endpoint
  ## Non-negotiable gotchas
  EOF
  cat > "$TARGET/docs/plans/demo/11-search-demand-endpoints/01-search-demand-endpoint.md" <<'EOF'
  # 01 — api: search-demand endpoint
  Coder: The Systemsmith
  Execution-profile: role-default
  Plan: ../11-search-demand-endpoints.md §1
  Reviewability: services/api only
  ## Do
  1. Build it. Cites AC 1.
  ## Checkpoint (green before 02)
  Seams under test: GET /api/admin/search-demand
  - pytest passes
  EOF

  RUN_A="$TMPD/run-a"
  mkdir -p "$RUN_A"
  cat > "$RUN_A/state.json" <<EOF
  {"workflow":"execute-plan","phase":"final","target_repo":"$TARGET","prompt_folder":"docs/plans/demo/11-search-demand-endpoints"}
  EOF
  cat > "$RUN_A/spec.md" <<'EOF'
  ## Requirements
  **AC 1** the endpoint returns 200
  EOF
  cat > "$RUN_A/plan.md" <<'EOF'
  ## Phase 1
  Implements AC 1.
  EOF

  out_a=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_A" --phase final 2>&1); rc_a=$?
  [ "$rc_a" -eq 0 ] || { echo "FAIL A: execute-plan run with a recorded prompt folder should pass --phase final: $out_a"; exit 1; }
  printf '%s\n' "$out_a" | grep -qF 'prompts.md' && { echo "FAIL A: must not mention prompts.md at all: $out_a"; exit 1; }

  # --- Case B: feature-style run, no prompts.md and no prompt folder recorded.
  # Must still FAIL --phase final with the presence defect (no regression).
  RUN_B="$TMPD/run-b"
  mkdir -p "$RUN_B"
  cat > "$RUN_B/state.json" <<'EOF'
  {"workflow":"feature","phase":"final","target_repo":"/dev/null"}
  EOF
  cat > "$RUN_B/spec.md" <<'EOF'
  ## Requirements
  **AC 1** something
  EOF
  cat > "$RUN_B/plan.md" <<'EOF'
  ## Phase 1
  Implements AC 1.
  EOF

  out_b=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_B" --phase final 2>&1); rc_b=$?
  [ "$rc_b" -eq 1 ] || { echo "FAIL B: a feature run with no prompts.md must still fail --phase final: $out_b"; exit 1; }
  printf '%s\n' "$out_b" | grep -qF 'prompts.md:0 — presence — required artifact absent: prompts.md' \
    || { echo "FAIL B: expected the prompts.md presence defect: $out_b"; exit 1; }

  echo PASS
expected: exit 0; stdout PASS. Mutation: revert the prompts-artifact resolution block back to the unconditional PROMPTS="$RUN_DIR/prompts.md" (and drop the state.json#prompt_folder read) and case A wrongly fails with "prompts.md:0 — presence — required artifact absent: prompts.md" even though the real prompt folder is complete.
