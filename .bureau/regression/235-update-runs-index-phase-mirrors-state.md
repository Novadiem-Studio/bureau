name: update-runs-index — mirrors state.json phase into the runs-index entry; missing entry is a silent no-op
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  URI="$ROOT/scripts/update-runs-index.sh"
  IDX="$ROOT/output/studio/runs-index"
  mkdir -p "$IDX"

  # Unique slug so this fixture never collides with a real run's index entry.
  SLUG="zzfixture235-$$"
  TMPF=$(mktemp -d)
  RUN_DIR="$TMPF/$SLUG"
  mkdir -p "$RUN_DIR"
  ENTRY="$IDX/$SLUG.json"
  # Always clean up the seeded index entry, pass or fail.
  trap 'rm -f "$ENTRY"; rm -rf "$TMPF"' EXIT

  # ── (c) FIRST: a missing runs-index entry is handled gracefully (exit 0, no create).
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":[],"phase_status":"pending","phase":"not_started","last_updated":null}' > "$RUN_DIR/state.json"
  bash "$URI" "$RUN_DIR"; rc=$?
  [ "$rc" -eq 0 ] || { echo "expected exit 0 for missing entry, got $rc"; exit 1; }
  [ ! -f "$ENTRY" ] || { echo "helper must NOT create a missing entry"; exit 1; }

  # Seed the initial index entry exactly as run-start.sh (step 7) would.
  printf '{"slug":"%s","repo":"/repo","run_dir":"%s","status":"not_started","phase":"not_started","last_updated":null,"workflow":"execute-plan"}\n' \
    "$SLUG" "$RUN_DIR" > "$ENTRY"

  # ── (a) PRE-FIX RED condition: state.json advances to the "build" phase, but WITHOUT
  # the helper the index entry would stay status:not_started / phase:not_started. Assert
  # the pre-call staleness so the RED baseline is explicit in the fixture.
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["analysis"],"phase_status":"in_progress","phase":"build","last_updated":"2026-08-09T11:30:00Z"}' > "$RUN_DIR/state.json"
  jq -e '.status == "not_started" and .phase == "not_started"' "$ENTRY" > /dev/null \
    || { echo "pre-call index entry not in the stale not_started baseline"; exit 1; }

  # ── (b) POST-FIX GREEN: call the helper; the entry now reflects in_progress + build phase +
  # the new last_updated, with the other 4 fields (slug/repo/run_dir/workflow) preserved.
  bash "$URI" "$RUN_DIR" || { echo "update-runs-index exited non-zero"; exit 1; }
  jq -e '
    .status == "in_progress"
    and .phase == "build"
    and .last_updated == "2026-08-09T11:30:00Z"
    and .slug == "'"$SLUG"'"
    and .repo == "/repo"
    and .workflow == "execute-plan"
  ' "$ENTRY" > /dev/null || { echo "index entry did not mirror state.json"; exit 1; }
  python3 -c "import json; json.load(open('$ENTRY'))" || { echo "entry not valid JSON"; exit 1; }

  # ── (b2) TERMINAL GUARD: phase_status is PER-PHASE, so it hits "complete" at every
  # intermediate phase boundary. A per-phase complete with a NON-terminal run-level phase
  # (more phases remain) must mirror in_progress, NOT complete — otherwise the index lies
  # complete mid-run (the inverse of Bug 3). This is the case that the terminal-complete
  # case below masks, because that one sets BOTH phase_status:complete AND phase:complete.
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["analysis"],"phase_status":"complete","phase":"architecture","last_updated":"2026-08-09T11:45:00Z"}' > "$RUN_DIR/state.json"
  bash "$URI" "$RUN_DIR" || { echo "update-runs-index (non-terminal complete) non-zero"; exit 1; }
  jq -e '.status == "in_progress" and .phase == "architecture"' "$ENTRY" > /dev/null \
    || { echo "per-phase complete with more phases remaining must be in_progress, not complete"; exit 1; }

  # A subsequent TERMINAL complete transition (run-level phase == "complete") mirrors status:complete.
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["analysis","build"],"phase_status":"complete","phase":"complete","last_updated":"2026-08-09T12:00:00Z"}' > "$RUN_DIR/state.json"
  bash "$URI" "$RUN_DIR" || { echo "update-runs-index (complete) non-zero"; exit 1; }
  jq -e '.status == "complete" and .phase == "complete"' "$ENTRY" > /dev/null \
    || { echo "terminal complete transition not mirrored"; exit 1; }

  # ── (d) ARCHIVED GUARD: a mis-timed call on an already-archived entry must never
  # un-archive it. Flip the entry to archived, advance state.json, and confirm it stays archived.
  jq '.status = "archived"' "$ENTRY" > "$ENTRY.t" && mv "$ENTRY.t" "$ENTRY"
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["analysis"],"phase_status":"in_progress","phase":"build","last_updated":"2026-08-09T13:00:00Z"}' > "$RUN_DIR/state.json"
  bash "$URI" "$RUN_DIR"; rc=$?
  [ "$rc" -eq 0 ] || { echo "archived-guard call should exit 0, got $rc"; exit 1; }
  jq -e '.status == "archived"' "$ENTRY" > /dev/null \
    || { echo "helper clobbered an archived entry (un-archived it)"; exit 1; }

  echo "PASS"
  # Mutation A: replace the case-based status derivation with a hardcoded status="not_started"
  # (the run-start.sh bug) and the (b) assertion .status=="in_progress" fails → RED.
  # Mutation B: drop the `phase == "complete"` terminal guard on the complete branch and
  # (b2) fails — the non-terminal per-phase complete wrongly mirrors complete.
  # Mutation C: drop the archived early-exit guard and (d) fails — archived is clobbered.
expected: exit 0; stdout "PASS"; helper mirrors state.json phase/status/last_updated into the runs-index entry (in_progress on build; per-phase complete with more phases remaining → in_progress; complete only at terminal close-out phase==complete), preserves slug/repo/run_dir/workflow, no-ops silently when the entry is absent, and never un-archives an archived entry
phase: bug-fix · build-tail-tooling-fixes
owner: Bug 3 / scripts/update-runs-index.sh (phase mirror into runs-index)
