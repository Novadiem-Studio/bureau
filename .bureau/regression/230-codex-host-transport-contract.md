name: Codex Bureau instructions map native fresh-context agents plus the isolated Spark one-shot transport explicitly
phase: multi-host Codex adapter
owner: AGENTS.md + CODEX.md + docs/host-runtime.md
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  H="$ROOT/docs/host-runtime.md"
  grep -Fq 'multi_agent_v1.spawn_agent' "$ROOT/AGENTS.md" \
    && grep -Fq 'scripts/run-codex-spark-specialist.sh' "$ROOT/AGENTS.md" \
    && grep -Fq '## Native Codex Bureau run' "$ROOT/CODEX.md" \
    && grep -Fq 'fork_turns: "none"' "$H" \
    && grep -Fq 'collaboration.followup_task' "$ROOT/CODEX.md" \
    && grep -Fq 'scripts/run-cold-reviewer.sh' "$H" \
    && grep -Fq '| Specialists | post-hoc Claude JSONL joined by SPAWN-EVENT `attempt_id` and the run-scope nonce; exact or explicitly degraded | unavailable |' "$H" \
    && grep -Fq '### Codex Spark execution profile' "$H" \
    && grep -Fq 'never enters `multi_agent_v1.spawn_agent`' "$H" \
    && echo PASS
expected: exit 0; stdout "PASS"; native Codex operation is explicit, fresh context is mandatory, resume is mapped, cold reviews share one helper, the specialist-accounting gap is named, and Spark uses only its one-shot helper.
