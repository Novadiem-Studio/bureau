name: aggregate-transcripts AC1 wash-killed proof is honest on the growing shared build-tail session
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  RUN_PATH="/Users/robin/Code/novadiem/bureau/.bureau/runs/20260809-build-tail-tooling-fixes"
  SID="8953531a-0955-4311-8105-e285ffd322a9"
  PROJECTS="${BUREAU_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  DELEGATE_TRANSCRIPT="$PROJECTS/-Users-robin-Code-novadiem-bureau/$SID.jsonl"
  CONDUCTOR_TRANSCRIPT="$PROJECTS/-Users-robin-Code-novadiem-bureau/$SID/subagents/agent-a4af8ed713bb82db6.jsonl"
  [ -r "$RUN_PATH/log.md" ] && [ -r "$DELEGATE_TRANSCRIPT" ] && [ -r "$CONDUCTOR_TRANSCRIPT" ] || exit 1
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>/dev/null) || exit 1
  printf '%s' "$out" | jq -e '
    .delegate.confidence == "partial" and
    .delegate.confidence != "exact" and
    (.delegate._note | type == "string" and length > 0) and
    (.delegate._note | contains("shared-session per-run window unavailable")) and
    .conductor.tokens.processed > 0
  ' >/dev/null || exit 1
  echo "PASS"
  # Shape-only by design: this shared transcript is still growing. Mutation:
  # delete the shared-session partial relabel and the confidence assertion fails.
expected: exit 0; stdout "PASS"; Delegate is partial with a note and Conductor is non-zero, with no token count pinned
phase: 03 · execute-plan
owner: Prompt 03 / AC1 exact-zero-wash-killed shape proof
