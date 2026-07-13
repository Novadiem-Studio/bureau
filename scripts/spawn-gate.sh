#!/usr/bin/env bash
# spawn-gate.sh — Pre-spawn gate: verify run-start.sh ceremony artifacts (FR 3).
#
# Mirrors preflight-artifacts.sh's exit-code + defect-line contract:
#   exit 0  + "gate: clean"  — all artifacts present; safe to spawn
#   exit 1  + DEFECT line(s) — one or more artifacts missing; do NOT spawn
#
# The Conductor calls this before the first specialist spawn and pipes its
# output to log.md (mirroring the preflight-gate logging pattern, FR 3).
# The gate re-checks at call time so a post-run-start deletion still fires (EC 3).
#
# Usage:
#   spawn-gate.sh <RUN_DIR>
#
# Bash 3.2 + jq; macOS portable. No set -e.

# Step 0: PATH pin (EC 10 — ugrep guard).
PATH=/usr/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Step 1: Argument validation ───────────────────────────────────────────────

RUN_DIR="$1"
if [ -z "$RUN_DIR" ]; then
  echo "Usage: spawn-gate.sh <RUN_DIR>" >&2
  exit 2
fi

# ── Step 2: Resolve pointer file path ─────────────────────────────────────────
#
# IDENTICAL path-resolution block to run-start.sh (and orchestrator.md § Pointer
# lifecycle lines 461-467) — ensures spawn-gate looks for the EXACT file that
# run-start.sh wrote.
#
# Precedence:
#   1. BUREAU_POINTER_FILE set (non-empty) → FORCED single-file mode.
#   2. Else → directory mode keyed by munged RUN_DIR under BUREAU_POINTER_DIR.

if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  _pointer_file="$BUREAU_POINTER_FILE"
else
  _pointer_dir="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  _ptr_key=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')   # munge / and . → -
  _pointer_file="$_pointer_dir/$_ptr_key"
fi

# ── Step 3: Check model-routing.json (present and non-empty) ─────────────────

defects=0

if [ ! -s "$RUN_DIR/model-routing.json" ]; then
  echo "DEFECT: model-routing.json absent or empty in RUN_DIR — run-start.sh may not have run"
  defects=$((defects + 1))
fi

# ── Step 4: Check pointer file (present) ─────────────────────────────────────

if [ ! -f "$_pointer_file" ]; then
  echo "DEFECT: pointer file absent at $_pointer_file — pointer enrolment did not run"
  defects=$((defects + 1))
fi

# ── Step 5: Gate verdict ──────────────────────────────────────────────────────

if [ "$defects" -eq 0 ]; then
  echo "gate: clean"
  exit 0
else
  exit 1
fi
