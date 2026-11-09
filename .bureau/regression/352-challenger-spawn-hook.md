name: the PreToolUse Agent hook denies a Challenger spawn on sonnet, haiku or no model, and lets opus/fable Challengers and every other role through
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  HOOK="$ROOT/scripts/challenger-spawn-hook.sh"
  run() { printf '%s' "$1" | bash "$HOOK"; }
  agent() { jq -cn --arg tool "$1" --argjson ti "$2" '{hook_event_name:"PreToolUse",tool_name:$tool,tool_input:$ti}'; }
  P_CH='You are running as The Challenger (the Critic) in the Agent Team Framework, spawned with a fresh context.\nRUN_DIR: /x\nAttempt ID: challenger-3'
  P_MAGE='You are running as The Mage (the Frontend) in the Agent Team Framework.\nAttempt ID: mage-1\nThe Challenger will review this diff after you finish.'
  fails=0
  expect_deny() {
    out=$(run "$2")
    printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
      || { echo "FAIL: expected deny for $1, got: $out"; fails=$((fails+1)); }
  }
  expect_allow() {
    out=$(run "$2")
    [ -z "$out" ] || { echo "FAIL: expected silent allow for $1, got: $out"; fails=$((fails+1)); }
  }
  # deny: role-line Challenger on sonnet / haiku / omitted model
  expect_deny "role-line sonnet"  "$(agent Agent "$(jq -cn --arg p "$P_CH" '{description:"Review round 3",prompt:$p,model:"sonnet"}')")"
  expect_deny "role-line haiku"   "$(agent Agent "$(jq -cn --arg p "$P_CH" '{description:"Review round 3",prompt:$p,model:"haiku"}')")"
  expect_deny "role-line omitted" "$(agent Agent "$(jq -cn --arg p "$P_CH" '{description:"Review round 3",prompt:$p}')")"
  # deny: other detection paths
  expect_deny "attempt-id critic-"  "$(agent Agent '{"description":"cold review","prompt":"Review the plan.\nAttempt ID: critic-01b","model":"sonnet"}')"
  expect_deny "subagent_type"       "$(agent Agent '{"description":"review","prompt":"review it","subagent_type":"critic","model":"sonnet"}')"
  expect_deny "description prefix"  "$(agent Agent '{"description":"Challenger round 2 on plan","prompt":"review it","model":"sonnet"}')"
  expect_deny "legacy Task tool"    "$(agent Task "$(jq -cn --arg p "$P_CH" '{description:"x",prompt:$p,model:"sonnet"}')")"
  # allow: strong and escalated Challengers
  expect_allow "challenger opus"  "$(agent Agent "$(jq -cn --arg p "$P_CH" '{description:"Review",prompt:$p,model:"opus"}')")"
  expect_allow "challenger fable" "$(agent Agent "$(jq -cn --arg p "$P_CH" '{description:"Review",prompt:$p,model:"fable"}')")"
  # allow: other roles on cheap models, even when they mention the Challenger
  expect_allow "mage sonnet mentioning challenger" "$(agent Agent "$(jq -cn --arg p "$P_MAGE" '{description:"Mage prompt 4",prompt:$p,model:"sonnet"}')")"
  expect_allow "scoot haiku on challenger findings" "$(agent Agent '{"description":"Scoot: grep the Challenger verdict","prompt":"You are running as Scoot. grep challenger-2 in log.md","model":"haiku"}')"
  expect_allow "conductor sonnet" "$(agent Agent '{"description":"Conductor resume","prompt":"You are running as The Conductor. Spawn The Challenger on opus at each gate. Read agents/critic.md for its modes.","model":"sonnet"}')"
  # allow: non-Agent tools and junk input (fail open)
  expect_allow "Bash tool" '{"tool_name":"Bash","tool_input":{"command":"echo You are running as The Challenger"}}'
  expect_allow "empty input" ''
  expect_allow "not json" 'garbage{'
  [ "$fails" = "0" ] && echo PASS
expected: PASS
