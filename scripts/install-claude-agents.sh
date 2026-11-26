#!/usr/bin/env bash
# install-claude-agents.sh: symlink claude-agents/*.md into ~/.claude/agents so Claude Code
# can spawn them by subagent_type. Safe to re-run. Sessions read agent types at startup, so
# a session that is already open does not see a new type.
#
# Refuses to link from a linked worktree (the links would break when it is removed) unless
# BUREAU_AGENTS_ALLOW_WORKTREE=1, and refuses to replace a real file. All checks run before
# the first link is made.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
dest="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"

git_dir="$(cd "$root" && cd "$(git rev-parse --git-dir)" && pwd -P)"
common_dir="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ "$git_dir" != "$common_dir" ] && [ "${BUREAU_AGENTS_ALLOW_WORKTREE:-}" != "1" ]; then
  echo "refusing to link from a worktree: $root. Run this from the main checkout." >&2
  exit 1
fi

for f in "$root"/claude-agents/*.md; do
  link="$dest/$(basename "$f")"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "refusing to replace a real file: $link" >&2
    exit 1
  fi
done

mkdir -p "$dest"
for f in "$root"/claude-agents/*.md; do
  link="$dest/$(basename "$f")"
  ln -sfn "$f" "$link"
  echo "$link -> $f"
done
