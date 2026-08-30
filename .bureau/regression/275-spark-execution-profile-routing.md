name: Model routing resolves Spark only as the OpenAI Mage granular UI profile with an honest Sol fallback
phase: Spark execution profile
owner: scripts/resolve-model-routing.sh + config/model-policy.v2.json + config/runtimes/openai.json
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/spark-routing.XXXXXX") || exit 2
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  mkdir -p "$TMP/empty-experiments"

  NOVADIEM_MODEL_RUNTIME=openai \
  NOVADIEM_MODEL_EXPERIMENTS_DIR="$TMP/empty-experiments" \
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMP/no-snapshot.json" \
    "$ROOT/scripts/resolve-model-routing.sh" "$TMP/openai.json" >/dev/null \
    || { echo "FAIL: OpenAI routing did not resolve"; exit 1; }

  jq -e '
    .runtime == "openai"
    and .roles.mage.model == "gpt-5.6-sol"
    and .roles.mage.reasoningEffort == "high"
    and (.roles.mage.executionProfiles["granular-ui-fast"] as $profile
      | $profile.model == "gpt-5.3-codex-spark"
      and $profile.reasoningEffort == "high"
      and $profile.transport == "codex-exec-one-shot"
      and $profile.helper == "scripts/run-codex-spark-specialist.sh"
      and $profile.fallback.kind == "role_default"
      and $profile.fallback.model == "gpt-5.6-sol"
      and $profile.fallback.reasoningEffort == "high")
    and ([.roles | to_entries[]
      | select(.key != "mage")
      | (.value.executionProfiles | length == 0)] | all)
  ' "$TMP/openai.json" >/dev/null \
    || { echo "FAIL: Spark leaked outside the qualified OpenAI Mage profile"; exit 1; }

  NOVADIEM_MODEL_RUNTIME=claude \
  NOVADIEM_MODEL_EXPERIMENTS_DIR="$TMP/empty-experiments" \
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMP/no-snapshot.json" \
    "$ROOT/scripts/resolve-model-routing.sh" "$TMP/claude.json" >/dev/null \
    || { echo "FAIL: Claude routing did not resolve"; exit 1; }

  jq -e '
    .runtime == "claude"
    and .roles.mage.model == "opus"
    and .roles.mage.reasoningEffort == null
    and ([.roles[].executionProfiles | length == 0] | all)
    and ((.roles | tostring | ascii_downcase | contains("spark")) | not)
  ' "$TMP/claude.json" >/dev/null \
    || { echo "FAIL: Claude routing was changed by the OpenAI-only Spark profile"; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS"; OpenAI Mage keeps Sol/high as its role default and gains Spark/high plus the one-shot helper and Sol/high fallback, every other OpenAI role has no execution profile, and Claude routing contains no Spark profile.
