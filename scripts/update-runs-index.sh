#!/usr/bin/env bash
# update-runs-index.sh <RUN_DIR> — mirror the current phase of a run into its
# runs-index entry.
#
# run-start.sh (step 7) writes the runs-index entry ONCE at run start with
# status:"not_started". Nothing updated it as state.json advanced, so the entry
# stayed "not_started" for the whole run until the archive step. This helper closes
# that gap: call it after every state.json phase update and the index entry tracks
# the live phase/status/last_updated.
#
# Usage:
#   ./scripts/update-runs-index.sh <RUN_DIR>
#
# Arguments:
#   <RUN_DIR>   absolute path to the run directory (contains state.json). Its
#               basename is the slug used to locate the runs-index entry.
#
# Behavior:
#   - Derives status from state.json (see the derivation table below).
#   - Reads phase and last_updated from state.json.
#   - Merges {status, phase, last_updated} into the existing runs-index entry
#     atomically (.tmp -> mv), preserving the other 4 fields (slug, repo, run_dir,
#     workflow).
#   - If the runs-index entry does not exist, exits 0 silently — creating it is
#     run-start.sh's job (step 7), not this helper's. It never fabricates an entry.
#   - The archive step owns the final complete->archived transition; do NOT call
#     this helper there.
#
# Exit codes:
#   0  entry updated, OR no entry to update (silent no-op)
#   1  error: bad args, RUN_DIR missing, state.json missing/unparseable, write failure

set -euo pipefail

die() { echo "update-runs-index: $*" >&2; exit 1; }

# ── argument handling ────────────────────────────────────────────────────────
[[ $# -eq 1 ]] || die "usage: update-runs-index.sh <RUN_DIR>"

RUN_DIR="$1"
[[ -d "$RUN_DIR" ]] || die "RUN_DIR does not exist or is not a directory: $RUN_DIR"

# Normalize RUN_DIR to an absolute path (strip a trailing slash so basename is clean).
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
SLUG="$(basename "$RUN_DIR")"

STATE_JSON="$RUN_DIR/state.json"
[[ -f "$STATE_JSON" ]] || die "state.json not found in RUN_DIR: $STATE_JSON"

# FRAMEWORK_ROOT is the parent of scripts/ (same pattern as run-start.sh, preflight.sh).
FRAMEWORK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX_ENTRY="$FRAMEWORK_ROOT/output/studio/runs-index/$SLUG.json"

# No entry yet → nothing to mirror. run-start.sh owns creation; exit clean and silent.
[[ -f "$INDEX_ENTRY" ]] || exit 0

# Never un-archive: the archive step owns the archived state (and moves the entry to
# runs-index/archive/). If a mis-timed call lands on an already-archived entry, exit
# clean without writing — a phase-mirror must never clobber archived → complete.
if [[ "$(jq -r '.status // ""' "$INDEX_ENTRY" 2>/dev/null)" == "archived" ]]; then
  exit 0
fi

# ── read state.json ──────────────────────────────────────────────────────────
# Guard the state.json read: a corrupt/non-object state.json is an error (exit 1),
# never a silent stale index. `2>/dev/null` keeps set -e from aborting before the check.
if ! jq -e 'type == "object"' "$STATE_JSON" >/dev/null 2>&1; then
  die "state.json is not a parseable JSON object: $STATE_JSON"
fi

phase="$(jq -r '.phase // "not_started"' "$STATE_JSON")"
phase_status="$(jq -r '.phase_status // ""' "$STATE_JSON")"
phases_len="$(jq '(.phases_complete // []) | length' "$STATE_JSON")"

# ── derive run-level status (docs/run-protocol.md § Run-level status derivation) ──
# The canonical index vocabulary is: not_started · blocked · in_progress · complete
# · archived (docs/run-protocol.md, docs/glossary.md). archived is the archive step's
# job, not this helper's; unknown is a last-resort sentinel for an unrecognized state.
#
# CRITICAL: `phase_status` is PER-PHASE (pending·in_progress·complete·blocked), so
# `phase_status == "complete"` fires at EVERY intermediate phase boundary (analysis done,
# build still ahead) — it is NOT the run-level terminal signal. The run-level TERMINAL
# close-out signal is the run-level `phase` LABEL reaching close-out (`.phase == "complete"`).
# Run-level "complete" is emitted ONLY at that terminal close-out; a per-phase "complete"
# with more phases ahead is "in_progress" (canonical table: "Phase complete but more phases
# remain (not terminal close-out) → in_progress"). Without this guard the index would flip to
# complete mid-run — inverting Bug 3's staleness the other way.
#   pending + empty phases_complete                      -> not_started
#   blocked                                              -> blocked
#   phase_status complete AND phase == "complete"        -> complete   (terminal close-out)
#   phase_status in_progress/complete (non-terminal),
#     or pending with phases already done                -> in_progress
#   anything else                                        -> unknown
case "$phase_status" in
  pending)
    if [[ "$phases_len" -eq 0 ]]; then status="not_started"; else status="in_progress"; fi
    ;;
  blocked)
    status="blocked"
    ;;
  in_progress)
    status="in_progress"
    ;;
  complete)
    # Per-phase complete. Only the run-level close-out label makes this terminal-complete;
    # otherwise more phases remain → in_progress.
    if [[ "$phase" == "complete" ]]; then status="complete"; else status="in_progress"; fi
    ;;
  *)
    if [[ "$phases_len" -gt 0 ]]; then status="in_progress"; else status="unknown"; fi
    ;;
esac

# ── merge status/phase/last_updated into the existing entry (atomic) ──────────
# Preserve slug, repo, run_dir, workflow verbatim; only the three live fields change.
# last_updated is copied from state.json (JSON null or an ISO-8601 string) via --argjson.
TMP="$FRAMEWORK_ROOT/output/studio/runs-index/.$SLUG.json.tmp"

jq \
  --arg status "$status" \
  --arg phase "$phase" \
  --argjson last_updated "$(jq '.last_updated' "$STATE_JSON")" \
  '.status = $status | .phase = $phase | .last_updated = $last_updated' \
  "$INDEX_ENTRY" > "$TMP" \
  || { rm -f "$TMP"; die "failed to build updated runs-index entry"; }

python3 -c "import json,sys; json.load(open('$TMP'))" \
  || { rm -f "$TMP"; die "updated runs-index entry is not valid JSON"; }

mv "$TMP" "$INDEX_ENTRY" \
  || { rm -f "$TMP"; die "failed to write runs-index entry"; }

exit 0
