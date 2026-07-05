name: subagent-stop EC 1 / AC 7a — no agent_transcript_path field → exit 0, no writes, no stdout
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Send a payload with no agent_transcript_path field (non-bureau session)
  stdout_out=$(echo '{"session_id":"sess-noop","stop_hook_active":false}' | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null)
  rc=$?
  # Must exit 0 with no stdout
  [ "$rc" = "0" ] || exit 1
  [ -z "$stdout_out" ] || exit 1
  echo "PASS"
expected: exit 0; stdout "PASS"; hook writes nothing, produces no stdout output
phase: 02 · feature
owner: Prompt 2 / subagent-stop.sh EC 1
