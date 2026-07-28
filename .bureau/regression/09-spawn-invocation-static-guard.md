name: provider-neutral cold reviewer: watcher delegates to one helper; Claude isolation flags and Codex permission-profile flags remain load-bearing
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WATCHER=$ROOT/scripts/watcher.sh
  HELPER=$ROOT/scripts/run-cold-reviewer.sh
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  strip "$WATCHER" | grep -Fq 'bash "$SCRIPT_DIR/run-cold-reviewer.sh"' && \
  ! strip "$WATCHER" | grep -q -- 'claude -p' && \
  ! strip "$HELPER" | grep -q -- '--bare' && \
  strip "$HELPER" | grep -Fq -- '--setting-sources ""' && \
  strip "$HELPER" | grep -q -- '--system-prompt' && \
  strip "$HELPER" | grep -Eq -- '--tools[[:space:]]+"Read"' && \
  strip "$HELPER" | grep -Fq -- '--add-dir "$CTX"' && \
  strip "$HELPER" | grep -Fq -- '--ignore-user-config' && \
  strip "$HELPER" | grep -Fq -- '--ignore-rules' && \
  strip "$HELPER" | grep -Fq -- 'default_permissions="bureau-review"' && \
  strip "$HELPER" | grep -Fq -- '--output-schema "$CODEX_SCHEMA"' && \
  echo "all-guards-present"
expected: prints "all-guards-present" — watcher has no provider-specific spawn and calls run-cold-reviewer.sh; the helper keeps Claude's proven Read-only/no-settings recipe and Codex's ephemeral no-user-config/no-rules permission-profile + output-schema recipe.
phase: multi-host Codex adapter
owner: scripts/watcher.sh + scripts/run-cold-reviewer.sh
