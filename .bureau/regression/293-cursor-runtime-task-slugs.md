name: Cursor runtime maps Task slugs and the spawn helper plans without launching
phase: multi-host Cursor adapter
owner: config/runtimes/cursor.json + scripts/run-cursor-specialist.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  R="$ROOT/config/runtimes/cursor.json"
  P="$ROOT/config/model-policy.v2.json"
  jq -e '
    .runtime == "cursor"
    and .tiers.cheap.model == "composer-2.5-fast"
    and .tiers.standard.model == "composer-2.5-fast"
    and .tiers.strong.model == "gpt-5.6-sol-medium"
    and .tiers.frontier.model == "cursor-grok-4.6-high-fast"
    and .tiers.escalated.model == "claude-opus-5-thinking-high"
    and .capabilities.supports_fresh_context_subagents == true
    and .capabilities.supports_cloud_subagents == true
  ' "$R" >/dev/null || { echo "FAIL: cursor runtime mapping drifted"; exit 1; }
  jq -e '
    .host_policy.cursor.allowed_spawn_models == [
      "composer-2.5-fast",
      "gpt-5.6-sol-medium",
      "cursor-grok-4.6-high-fast",
      "claude-opus-5-thinking-high"
    ]
    and ((.host_policy.cursor.forbidden | index("inherit")) != null)
  ' "$P" >/dev/null || { echo "FAIL: cursor host policy missing"; exit 1; }

  TMP=$(mktemp -d "${TMPDIR:-/tmp}/cursor-routing.XXXXXX") || exit 2
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  NOVADIEM_MODEL_RUNTIME=cursor \
  NOVADIEM_USAGE_SNAPSHOT_PATH="$TMP/no-snapshot.json" \
    "$ROOT/scripts/resolve-model-routing.sh" "$TMP/routing.json" >/dev/null \
    || { echo "FAIL: Cursor routing did not resolve"; exit 1; }
  jq -e '
    .runtime == "cursor"
    and .roles.conductor.model == "gpt-5.6-sol-medium"
    and .roles.challenger.model == "gpt-5.6-sol-medium"
    and .roles.analyst.model == "composer-2.5-fast"
    and .roles.scoot.model == "composer-2.5-fast"
  ' "$TMP/routing.json" >/dev/null \
    || { echo "FAIL: Cursor resolved roles drifted"; exit 1; }

  mkdir -p "$TMP/run"
  cp "$TMP/routing.json" "$TMP/run/model-routing.json"
  printf 'you are the analyst\n' > "$TMP/prompt.md"
  set +e
  plan="$("$ROOT/scripts/run-cursor-specialist.sh" --plan --environment local \
    "$TMP/run" analyst "$TMP/prompt.md" analyst-1 2>"$TMP/stderr")"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || { echo "FAIL: helper rc was $rc, expected 2"; exit 1; }
  printf '%s' "$plan" | jq -e '
    .runtime == "cursor"
    and .status == "host-task-required"
    and .environment == "local"
    and .fork_context == false
    and .model == "composer-2.5-fast"
    and .isolation.ok == true
  ' >/dev/null || { echo "FAIL: plan payload drifted"; cat "$TMP/stderr"; exit 1; }
  grep -q 'CURSOR-TRANSPORT-HOST-TASK-REQUIRED' "$TMP/stderr" \
    || { echo "FAIL: missing host-task required line"; exit 1; }

  set +e
  "$ROOT/scripts/run-cursor-specialist.sh" --plan --environment cloud \
    "$TMP/run" challenger "$TMP/prompt.md" challenger-1 >/dev/null 2>"$TMP/cloud-stderr"
  cloud_rc=$?
  set -e
  [ "$cloud_rc" -eq 2 ] || { echo "FAIL: cloud challenger rc was $cloud_rc"; exit 1; }
  grep -q 'cold roles' "$TMP/cloud-stderr" \
    || { echo "FAIL: cloud challenger was not rejected"; exit 1; }

  skip="$("$ROOT/scripts/resolve-delegate-affordability.sh" cursor "$TMP/absent.json")" \
    || { echo "FAIL: affordability cursor skip failed"; exit 1; }
  [ "$skip" = '{"action":"skip","source":"runtime"}' ] \
    || { echo "FAIL: affordability did not skip cursor"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; Cursor adapter maps Task slugs, the helper plans without launching, cloud Challenger is rejected, and affordability skips.
