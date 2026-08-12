name: account-run.sh — a quota downgrade (actual!=configured, no hand override) auto-emits ONE MODEL-OVERRIDE line and stops reading as a violation; idempotent on re-run
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  AR="$ROOT/scripts/account-run.sh"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/run"; mkdir -p "$RP"

  # A genuine quota downgrade: model-routing gives mage=opus, but the honest SPAWN-EVENT
  # carries actual_model=sonnet (the Conductor picked the downgrade and logged it). There
  # is NO hand-written MODEL-OVERRIDE line. Pre-fix, FR12 flagged this as a permanent
  # "model divergence without override" violation because nothing ever emits the override.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"opus","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-08-11T10:00:00Z"}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"opus","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-08-11T10:05:00Z","started_at":"2026-08-11T10:00:00Z"}' \
    > "$RP/log.md"
  printf '%s\n' '{"workflow":"execute-plan","phases_complete":["build"],"phase_status":"complete","critic_loops":{}}' > "$RP/state.json"
  printf '%s\n' '{"roles":{"mage":{"model":"opus"}}}' > "$RP/model-routing.json"

  bash "$AR" "$RP" >/dev/null 2>&1 || { echo "FAIL: account-run (1st) non-zero"; exit 1; }

  # (1) The divergence no longer reads as a violation — top-level flag absent, mage _note
  #     carries no "model divergence".
  jq -e '(._model_divergence_note // null) == null
         and ((.specialist_spawns[] | select(.role.value=="mage") | ._note // "") | test("model divergence") | not)
        ' "$RP/accounting.json" > /dev/null \
    || { echo "FAIL: divergence still flagged as violation: $(jq -c '{top:._model_divergence_note, mage:(.specialist_spawns[]|select(.role.value=="mage")|._note)}' "$RP/accounting.json")"; exit 1; }

  # (2) Exactly ONE MODEL-OVERRIDE line was appended to log.md for mage-1, matching the
  #     divergence by attempt_id+configured+actual, with the auto-reconcile reason and an
  #     `at` field (shell-computed date -u — present, not asserted for a literal value).
  n1=$(PATH=/usr/bin:$PATH grep -c '^MODEL-OVERRIDE:' "$RP/log.md")
  [ "$n1" = "1" ] || { echo "FAIL: expected 1 MODEL-OVERRIDE line after 1st run, got $n1"; exit 1; }
  line=$(PATH=/usr/bin:$PATH grep '^MODEL-OVERRIDE:' "$RP/log.md" | head -1); line="${line#MODEL-OVERRIDE: }"
  echo "$line" | jq -e '.role=="mage" and .attempt_id=="mage-1" and .configured=="opus" and .actual=="sonnet"
                        and (.reason | test("auto-reconciled")) and (.at | type=="string" and (test("Z$")))' > /dev/null \
    || { echo "FAIL: emitted MODEL-OVERRIDE line malformed: $line"; exit 1; }

  # (3) IDEMPOTENT: a SECOND account-run.sh invocation (accounting is re-runnable) must
  #     NOT append a duplicate line, and the divergence must still be reconciled.
  bash "$AR" "$RP" >/dev/null 2>&1 || { echo "FAIL: account-run (2nd) non-zero"; exit 1; }
  n2=$(PATH=/usr/bin:$PATH grep -c '^MODEL-OVERRIDE:' "$RP/log.md")
  [ "$n2" = "1" ] || { echo "FAIL: 2nd run appended a duplicate MODEL-OVERRIDE line (got $n2)"; exit 1; }
  jq -e '(._model_divergence_note // null) == null' "$RP/accounting.json" > /dev/null \
    || { echo "FAIL: divergence re-flagged on 2nd run"; exit 1; }

  echo "PASS"
  # Mutation note: remove the auto-emit/reconcile block in scripts/account-run.sh (the
  # post-hoc reconcile at the FR12 divergence site — the `printf 'MODEL-OVERRIDE: ...'`
  # append and the "leave divergence_note empty" comment) and restore
  #   divergence_note="model divergence without override: ..."
  # → no override line is written, the violation note returns → (1)/(2) fail → RED.
expected: exit 0; stdout "PASS"; a genuine quota downgrade (actual!=configured, no hand-written override) auto-emits exactly one MODEL-OVERRIDE line for the spawn (auto-reconcile reason, shell-computed `at`), drops the "model divergence without override" violation, and a second account-run.sh run does not duplicate the line.
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 4 / scripts/account-run.sh FR12 post-hoc MODEL-OVERRIDE auto-reconcile (idempotent)
