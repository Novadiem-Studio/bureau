#!/usr/bin/env bash
# check-drift.sh — diff per-project copies against this canonical repo.
#
# As of 2026-06-13 there are NO per-project framework copies: the studio runs from this
# ONE global install (see docs/git-worktree.md). The old GrowOperative and Oriva copies
# were retired to output-only archives (history kept for Society Desk); their pre-retire
# state is in ../_retired-framework-copies-20260613/. Run from any project by pointing at
# this install's CLAUDE.md — nothing to sync. This script now only checks installs you
# pass explicitly, for the rare case a copy is spun up again.
#
# Usage:
#   ./check-drift.sh /path/to/install ... # check specific installs (none tracked by default)
#
# Per-project files (output/, project-context.md, .claude/) are excluded — only the
# framework itself (agents/, workflows/, templates/, CLAUDE.md, README.md) is compared.
# Exit 0 = all in sync, 1 = drift found.
set -euo pipefail

CANON="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -gt 0 ]; then
  INSTALLS=("$@")
else
  # Centralized: one global install, no per-project copies to track.
  INSTALLS=()
fi

if [ "${#INSTALLS[@]}" -eq 0 ]; then
  echo "One global install — no per-project copies to drift-check. Pass paths to check specific installs."
  exit 0
fi

EXCLUDES=(-x output -x project-context.md -x .claude -x .git -x .DS_Store -x check-drift.sh -x check-framework.sh)

status=0
for install in "${INSTALLS[@]}"; do
  echo "== ${install}"
  if [ ! -d "$install" ]; then
    echo "   MISSING — not found"
    status=1
    continue
  fi
  if diff -rq "${EXCLUDES[@]}" "$CANON" "$install" | sed 's/^/   /'; then
    echo "   in sync"
  else
    status=1
  fi
done

exit $status
