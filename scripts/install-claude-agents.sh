#!/usr/bin/env bash
# install-claude-agents.sh: symlink claude-agents/*.md into ~/.claude/agents so Claude Code
# can spawn them by subagent_type. Safe to re-run. Refuses to replace a real file.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
mkdir -p "$dest"
for f in "$root"/claude-agents/*.md; do
  link="$dest/$(basename "$f")"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "refusing to replace a real file: $link" >&2
    exit 1
  fi
  ln -sfn "$f" "$link"
  echo "$link -> $f"
done
