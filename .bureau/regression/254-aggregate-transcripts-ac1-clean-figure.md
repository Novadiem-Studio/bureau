name: aggregate-transcripts AC1 clean figure stays exact on the stable gigcaravan single-session run
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  RUN_PATH="/Users/robin/Code/novadiem/gigcaravan/gigcaravan-adonis/.bureau/runs/20260810-scaffold-pipeline-tracker"
  SID="6f853d70-3d48-40d5-86a8-6de29472a1da"
  PROJECTS="${BUREAU_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  [ -r "$RUN_PATH/log.md" ] || exit 1
  grep -q '^DELEGATE-TOKEN-EVENT: .*"session_id":"6f853d70-3d48-40d5-86a8-6de29472a1da"' "$RUN_PATH/log.md" || exit 1
  transcripts=$(find "$PROJECTS" -mindepth 2 -maxdepth 2 -name "$SID.jsonl" -type f -print)
  [ "$(printf '%s\n' "$transcripts" | awk 'NF {n++} END {print n+0}')" -eq 1 ] || exit 1
  transcript=$(printf '%s\n' "$transcripts" | awk 'NF {print; exit}')
  . "$ROOT/scripts/lib/bureau-token-lib.sh"
  usage=$(sum_transcript_usage "$transcript") || exit 1
  printf '%s' "$usage" | jq -e '.processed == 97226341 and .turns == 144' >/dev/null || exit 1
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$PROJECTS" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>/dev/null) || exit 1
  printf '%s' "$out" | jq -e '
    .delegate.tokens.processed == 97226341 and
    .delegate.turns == 144 and
    .delegate.confidence == "exact" and
    (.delegate | has("_note") | not)
  ' >/dev/null || exit 1
  echo "PASS"
  # Mutation: remove the target-root equivalent from delegate_run_header_identities;
  # the relocated proof run is falsely labelled partial and this fixture fails.
expected: exit 0; stdout "PASS"; stable Delegate whole-file usage is processed=97226341, turns=144, confidence exact
phase: 03 · execute-plan
owner: Prompt 03 / AC1 stable clean-figure proof
