name: preflight-design-build-no-spec (D1 — design-build workflow skips spec.md presence check)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: scripts/preflight-artifacts.sh — design-build workflow exemption (D1 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  RUN_DIR="$TMPD/run"
  mkdir -p "$RUN_DIR"
  # Write state.json marking workflow as design-build
  cat > "$RUN_DIR/state.json" <<'EOF'
  {"workflow":"design-build","phase":"round1","target_repo":"/dev/null"}
  EOF
  # Write plan.md only (no spec.md — design-build doesn't produce one)
  cat > "$RUN_DIR/plan.md" <<'EOF'
  ## Phase 1
  Build step content.
  EOF
  out=$(bash "$ROOT/scripts/preflight-artifacts.sh" "$RUN_DIR" --phase round1 2>&1); rc=$?
  # Must NOT exit 1 from a missing-spec false-positive
  [ "$rc" -ne 1 ] || { echo "FAIL: exited 1 — design-build triggered spec-presence check: $out"; exit 1; }
  # Must NOT flag spec.md as absent
  printf '%s\n' "$out" | grep -qF 'spec.md' && { echo "FAIL: spec.md mentioned in output (should be exempt): $out"; exit 1; }
  echo "PASS"
  # Mutation note: remove the WORKFLOW detection block from preflight-artifacts.sh
  # (the lines that read state.json and set WORKFLOW="design-build"). The script
  # then exits 1 with "required artifact absent: spec.md", and the grep-qF check
  # triggers, making the fixture fail.
expected: PASS
