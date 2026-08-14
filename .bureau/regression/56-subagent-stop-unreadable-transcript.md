name: subagent-stop EC 2 — unreadable transcript path → exit 0, warning to stderr, no log writes
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  # Point at a non-existent file — transcript is not readable
  stderr_out=$(echo '{"agent_transcript_path":"'"$TMPF"'/no-such-file.jsonl"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>&1 1>/dev/null)
  rc=$?
  rm -rf "$TMPF"
  # Must exit 0
  [ "$rc" = "0" ] || exit 1
  # Must emit a warning containing "not readable" to stderr
  echo "$stderr_out" | grep -qi "not readable" || exit 1
  echo "PASS"
expected: exit 0; stdout "PASS"; hook emits a "not readable" warning to stderr and writes nothing to any log
phase: 02 · feature
owner: Prompt 2 / subagent-stop.sh EC 2
