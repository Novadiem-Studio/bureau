name: OpenAI runtime keeps Sol/Terra on native spawns and reserves Spark for the explicit one-shot execution profile
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
    and .execution_profiles["granular-ui-fast"].model == "gpt-5.3-codex-spark"
    and .execution_profiles["granular-ui-fast"].reasoning_effort == "high"
    and .execution_profiles["granular-ui-fast"].transport == "codex-exec-one-shot"
    and .execution_profiles["granular-ui-fast"].helper == "scripts/run-codex-spark-specialist.sh"
  ' "$R" >/dev/null || { echo "FAIL: openai runtime mapping drifted"; exit 1; }
  jq -e '
    .host_policy.openai.allowed_spawn_models == ["gpt-5.6-terra", "gpt-5.6-sol"]
    and .host_policy.openai.allowed_exec_models == ["gpt-5.3-codex-spark"]
    and .execution_profiles["granular-ui-fast"].fallback == "role_default"
    and .roles.mage.allowed_profiles == ["granular-ui-fast"]
  ' "$P" >/dev/null || { echo "FAIL: openai host policy missing"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; economical and demanding native roles remain on Terra/Sol while Spark/high is available only through the named one-shot Mage profile.
