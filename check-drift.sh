#!/usr/bin/env bash
# check-drift.sh — diff LEGACY per-project copies against this canonical repo.
# Prefer one global install (see docs/git-worktree.md, README.md). Remove old copies when migrated.
#
# Usage:
#   ./check-drift.sh                      # check the known installs listed below
#   ./check-drift.sh /path/to/install ... # check specific installs
#
# Per-project files (output/, project-context.md, .claude/) are excluded — only the
# framework itself (agents/, workflows/, templates/, CLAUDE.md, README.md) is compared.
# Exit 0 = all in sync, 1 = drift found.
set -euo pipefail

CANON="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -gt 0 ]; then
  INSTALLS=("$@")
else
  # Known installs — add a line here whenever the framework is copied into a new project.
  INSTALLS=(
    "$HOME/Code/novadiem/oriva/agent-framework"
    "$HOME/Code/foaftech/Growoperative/agent-framework"
  )
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
