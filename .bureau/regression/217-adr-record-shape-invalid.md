name: adr-record-shape-invalid
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  TARGET="$(mktemp -d)"
  trap 'rm -rf "$TMP" "$TARGET"' EXIT
  mkdir -p "$TARGET/docs/adr"
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — ADR shape**
  Malformed ADRs are mechanically rejected.

  **AC 1.** Invalid ADR status and heading shape fail preflight.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  cat > "$TMP/state.json" <<STATE
  {"target_repo":"$TARGET"}
  STATE
  cat > "$TARGET/docs/adr/0002-bad-status.md" <<'ADR'
  # ADR-0007: Bad Status
  Status: maybe
  Date: 2026-07-21

  ## Context
  This record has a mismatched heading and invalid status.

  ## Decision
  Keep the malformed record for the negative fixture.
  ADR
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" 2>&1)"
  EC=$?
  echo "$OUT"
  echo "exit:$EC"
  [ "$EC" -eq 1 ] || { echo "FAIL: expected exit 1, got $EC"; exit 1; }
  echo "$OUT" | grep -qF 'adr-heading' || { echo "FAIL: output does not name adr-heading"; exit 1; }
  echo "$OUT" | grep -qF 'adr-status' || { echo "FAIL: output does not name adr-status"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  script output includes adr-heading and adr-status for docs/adr/0002-bad-status.md, then exit:1
phase: 01 · feature (Bundle 35)
owner: scripts/preflight-artifacts.sh check_adr_records
