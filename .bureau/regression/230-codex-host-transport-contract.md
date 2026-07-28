name: Codex Bureau instructions authorize fresh-context subagents and map spawn, resume, reviewer, and accounting behavior explicitly
phase: multi-host Codex adapter
owner: AGENTS.md + CODEX.md + docs/host-runtime.md
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  H="$ROOT/docs/host-runtime.md"
  grep -Fq 'collaboration.spawn_agent' "$ROOT/AGENTS.md" \
    && grep -Fq '## Native Codex Bureau run' "$ROOT/CODEX.md" \
    && grep -Fq 'fork_turns: "none"' "$H" \
    && grep -Fq 'collaboration.followup_task' "$H" \
    && grep -Fq 'scripts/run-cold-reviewer.sh' "$H" \
    && grep -Fq '| Specialists | exact SubagentStop event by attempt/nonce | unavailable |' "$H" \
    && echo PASS
expected: exit 0; stdout "PASS"; native Codex operation is explicit, fresh context is mandatory, resume is mapped, cold reviews share one helper, and the specialist-accounting gap is named rather than hidden.
