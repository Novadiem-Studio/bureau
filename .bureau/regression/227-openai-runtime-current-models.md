name: OpenAI runtime reserves Astra for escalation and Spark for the explicit one-shot execution profile
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
    and .tiers.escalated.model == "gpt-6-astra"
    and .tiers.strong.reasoning_effort == "high"
    and .tiers.escalated.reasoning_effort == "max"
    and .execution_profiles["granular-ui-fast"].model == "gpt-5.3-codex-spark"
    and .execution_profiles["granular-ui-fast"].reasoning_effort == "high"
    and .execution_profiles["granular-ui-fast"].transport == "codex-exec-one-shot"
    and .execution_profiles["granular-ui-fast"].helper == "scripts/run-codex-spark-specialist.sh"
  ' "$R" >/dev/null || { echo "FAIL: openai runtime mapping drifted"; exit 1; }
  jq -e '
    .host_policy.openai.allowed_spawn_models == ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra"]
    and .host_policy.openai.allowed_exec_models == ["gpt-5.3-codex-spark"]
    and .execution_profiles["granular-ui-fast"].fallback == "role_default"
    and .roles.mage.allowed_profiles == ["granular-ui-fast"]
  ' "$P" >/dev/null || { echo "FAIL: openai host policy missing"; exit 1; }

  TMP=$(mktemp -d "${TMPDIR:-/tmp}/astra-routing.XXXXXX") || exit 2
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  mkdir -p "$TMP/experiments"
  cat > "$TMP/experiments/astra-escalation-fixture.json" <<'JSON'
  {
    "id": "astra-escalation-fixture",
    "activate_when": { "manual_only": true },
    "overrides": { "conductor": "escalated" }
  }
  JSON
  NOVADIEM_MODEL_RUNTIME=openai \
  NOVADIEM_MODEL_EXPERIMENTS=astra-escalation-fixture \
  NOVADIEM_MODEL_EXPERIMENTS_DIR="$TMP/experiments" \
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMP/no-snapshot.json" \
    "$ROOT/scripts/resolve-model-routing.sh" "$TMP/routing.json" >/dev/null \
    || { echo "FAIL: OpenAI routing did not resolve"; exit 1; }
  jq -e '
    .runtime == "openai"
    and .roles.conductor.tier == "escalated"
    and .roles.conductor.model == "gpt-6-astra"
    and .roles.conductor.reasoningEffort == "max"
    and .roles.challenger.model == "gpt-5.6-sol"
    and .roles.analyst.model == "gpt-5.6-terra"
  ' "$TMP/routing.json" >/dev/null \
    || { echo "FAIL: Astra did not remain escalation-only in resolved routing"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; economical and demanding first-pass roles remain on Terra/Sol, Astra/max is escalation-only, and Spark/high is available only through the named one-shot Mage profile.
