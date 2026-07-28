name: OpenAI runtime and host policy use the current Codex Sol/Terra model family with explicit reasoning tiers
phase: multi-host Codex adapter
owner: config/runtimes/openai.json + config/model-policy.v2.json
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  R="$ROOT/config/runtimes/openai.json"
  P="$ROOT/config/model-policy.v2.json"
  jq -e '
    .runtime == "openai"
    and .tiers.cheap.model == "gpt-5.6-terra"
    and .tiers.standard.model == "gpt-5.6-terra"
    and .tiers.strong.model == "gpt-5.6-sol"
    and .tiers.frontier.model == "gpt-5.6-sol"
    and .tiers.escalated.model == "gpt-5.6-sol"
    and .tiers.strong.reasoning_effort == "high"
    and .tiers.escalated.reasoning_effort == "max"
  ' "$R" >/dev/null || { echo "FAIL: openai runtime mapping drifted"; exit 1; }
  jq -e '
    (.host_policy.openai.allowed_spawn_models | index("gpt-5.6-terra")) != null
    and (.host_policy.openai.allowed_spawn_models | index("gpt-5.6-sol")) != null
  ' "$P" >/dev/null || { echo "FAIL: openai host policy missing"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; economical roles map to gpt-5.6-terra, demanding roles map to gpt-5.6-sol, and the policy allowlists both.
