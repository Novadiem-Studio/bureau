name: adr-record-shape-valid
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP="$(mktemp -d)"
  TARGET="$(mktemp -d)"
  trap 'rm -rf "$TMP" "$TARGET"' EXIT
  mkdir -p "$TARGET/docs/adr"
  cat > "$TMP/spec.md" <<'SPEC'
  **FR 1 — ADR shape**
  Accepted ADRs are mechanically linted.

  **AC 1.** A valid ADR shape passes preflight.
  SPEC
  cat > "$TMP/plan.md" <<'PLAN'
  This implements FR 1.
  PLAN
  cat > "$TMP/state.json" <<STATE
  {"target_repo":"$TARGET"}
  STATE
  cat > "$TARGET/docs/adr/0001-postgres-write-model.md" <<'ADR'
  # ADR-0001: Postgres Write Model
  Status: accepted
  Date: 2026-07-21

  ## Context
  The write model needs transactional constraints across records.

  ## Decision
  Use Postgres as the write model.

  ## Consequences
  Migrations become part of delivery.
  ADR
  OUT="$("$ROOT/scripts/preflight-artifacts.sh" "$TMP" 2>&1)"
  EC=$?
  echo "$OUT"
  [ "$EC" -eq 0 ] || { echo "FAIL: expected exit 0, got $EC"; exit 1; }
  echo "$OUT" | grep -qx 'preflight: clean' || { echo "FAIL: expected clean preflight"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout includes preflight: clean and ends with PASS
phase: 01 · feature (Bundle 35)
owner: scripts/preflight-artifacts.sh check_adr_records
