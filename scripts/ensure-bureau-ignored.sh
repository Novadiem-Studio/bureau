#!/usr/bin/env bash
# Ensure .bureau/runs/ and .bureau/archive/ are gitignored in a target repo.
#
# Usage:
#   ./scripts/ensure-bureau-ignored.sh <repo>
#
# Arguments:
#   <repo>   absolute path to a git repository
#
# Exit codes:
#   0  both entries are now present in .gitignore (added or already there)
#   1  bad arguments, repo not a directory, or .gitignore not writable
#
# IMPORTANT: the entries appended are EXACTLY:
#   .bureau/runs/
#   .bureau/archive/
# NEVER a blanket .bureau/ entry — because .bureau/regression/ is a committed,
# tracked fixture suite and a blanket entry would silently un-track it.
#
# The same entries are ALSO written to .git/info/exclude. .gitignore is branch
# content: an old branch that predates these entries un-ignores .bureau/runs/
# the moment it is checked out, and a GUI "discard changes" then deletes every
# run dir (this destroyed 4 runs' state in mot on 2026-07-05 via GitHub Desktop
# branch browsing). info/exclude is repo-local and branch-independent — it
# holds on every branch, which is the actual protection.

set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "ensure-bureau-ignored: $*" >&2; exit 1; }

# ── argument handling ────────────────────────────────────────────────────────

[[ $# -eq 1 ]] || { echo "ensure-bureau-ignored: expected exactly one argument: <repo>" >&2; usage 1; }

REPO="$1"

[[ -d "$REPO" ]] || die "not a directory: $REPO"

GITIGNORE="$REPO/.gitignore"

# ── idempotent append for each scoped entry ──────────────────────────────────

append_if_missing() {
  local entry="$1"
  local path_to_test="$2"

  if git -C "$REPO" check-ignore --quiet "$path_to_test" 2>/dev/null; then
    # Already ignored — nothing to do
    return 0
  fi

  # Not ignored — append to .gitignore (creating it if absent)
  printf '%s\n' "$entry" >> "$GITIGNORE" || die "cannot write to $GITIGNORE"
}

append_if_missing ".bureau/runs/"    "$REPO/.bureau/runs/x"
append_if_missing ".bureau/archive/" "$REPO/.bureau/archive/x"

# ── branch-independent belt: .git/info/exclude ───────────────────────────────
# check-ignore above may be satisfied by a .gitignore entry that exists only on
# the CURRENT branch. info/exclude is not version-controlled, so it protects
# run dirs on every branch, including old ones that predate the entries.

EXCLUDE="$(git -C "$REPO" rev-parse --git-path info/exclude)"
# rev-parse may return a path relative to the repo root
[[ "$EXCLUDE" = /* ]] || EXCLUDE="$REPO/$EXCLUDE"
mkdir -p "$(dirname "$EXCLUDE")"
touch "$EXCLUDE"
for entry in ".bureau/runs/" ".bureau/archive/"; do
  grep -qxF "$entry" "$EXCLUDE" || printf '%s\n' "$entry" >> "$EXCLUDE" \
    || die "cannot write to $EXCLUDE"
done

exit 0
