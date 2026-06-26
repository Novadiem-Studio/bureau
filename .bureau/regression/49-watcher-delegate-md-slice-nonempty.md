name: F-slice · W-d awk slice of agents/delegate.md is NON-EMPTY and carries the Critic checklist + DELEGATE FLAG guard
command: |
  # ── SEQUENCING (READ FIRST) ────────────────────────────────────────────────
  # RUN ONLY AFTER Prompt 5 (Phase 3) writes the COLD-REVIEWER-MODE:BEGIN/END
  # markers into agents/delegate.md. Until P5 lands, the awk slice is EMPTY and
  # this fixture BLOCKS by design (that is the point — it guards the W-b staging
  # change that Prompt 4 wired). The Conductor must NOT run it before P5.
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
  # The exact W-d slice recipe used by watcher.sh (and the v2 stager), bridge v2 §4.
  awk '/^# COLD-REVIEWER-MODE:BEGIN/,/^# COLD-REVIEWER-MODE:END/' \
    "$ROOT/agents/delegate.md" > "$TMP"
  [ -s "$TMP" ] || { echo "FAIL: slice empty — COLD-REVIEWER-MODE markers absent (pre-Prompt-5?)"; exit 1; }
  grep -q 'Critic checklist' "$TMP" || { echo "FAIL: 6-item Critic checklist marker missing from slice"; exit 1; }
  grep -q 'DELEGATE FLAG'    "$TMP" || { echo "FAIL: DELEGATE FLAG guard text missing from slice"; exit 1; }
  echo PASS
expected: exit 0 — prints PASS once Prompt 5's COLD-REVIEWER-MODE:BEGIN/END markers exist: the awk slice of agents/delegate.md is non-empty AND contains the "Critic checklist" marker AND the "DELEGATE FLAG" guard text. Nonzero if the markers are missing (empty slice) or the sliced section omits the critic checklist or the DELEGATE FLAG guard. Mutation-test: deleting either COLD-REVIEWER-MODE marker from agents/delegate.md empties the slice and fails this fixture.
phase: 2b · execute-plan (Bundle 15 P4) — RUN ONLY AFTER Prompt 5 (Phase 3) writes the COLD-REVIEWER-MODE markers; Blocker (not slow) once it runs
owner: prompts.md Prompt 4 (scripts/watcher.sh W-d slice) → markers authored by Prompt 5 (agents/delegate.md)
