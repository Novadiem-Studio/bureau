#!/usr/bin/env bash
# challenger-spawn-hook.sh: Claude Code PreToolUse hook on the Agent (and legacy Task) tool.
#
# Refuses to spawn The Challenger below the strong tier (issue #135, follow-up to #133).
# preflight-artifacts.sh catches a sub-strong Challenger only after it has run, at the next
# checkpoint; this hook stops it at the spawn.
#
# Rule: a spawn that is a Challenger must pass `model` as opus or fable. Anything else is
# denied, including an omitted model, because an omitted model inherits the session model,
# and a quota-downgraded Conductor is on sonnet.
#
# A spawn counts as a Challenger when any of these hold (orchestrator.md § How to spawn):
#   - subagent_type is "challenger" or "critic"
#   - the prompt OPENS with the role line "You are running as The Challenger" (quoted
#     elsewhere in a prompt it does not count: a test or Conductor brief may quote it)
#   - a line of the prompt starts "Attempt ID: challenger-..." or "Attempt ID: critic-..."
#   - the description starts with "Challenger" or "The Challenger"
# Every other spawn passes untouched.
#
# Fails open: unreadable input, a missing jq, or a non-Agent tool all exit 0 with no output.
# Wiring (~/.claude/settings.json, hooks.PreToolUse):
#   { "matcher": "Agent|Task", "hooks": [ { "type": "command", "timeout": 5,
#     "command": "/bin/sh -c '[ -x \"$0\" ] && exec \"$0\"; exit 0' <bureau>/scripts/challenger-spawn-hook.sh" } ] }

PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH

command -v jq >/dev/null 2>&1 || exit 0
hook_input="$(cat)" || exit 0
[ -n "$hook_input" ] || exit 0

tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
case "$tool_name" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

is_challenger="$(printf '%s' "$hook_input" | jq -r '
  (.tool_input // {}) as $t
  | (($t.subagent_type // "") | ascii_downcase) as $st
  | (($t.prompt // "") | tostring) as $p
  | (($t.description // "") | tostring) as $d
  | if ($st == "challenger" or $st == "critic")
      or ($p | test("\\A\\s*You are running as The Challenger"; "i"))
      or ($p | test("(\\A|\\n)[ \\t]*Attempt ID:[ \\t]*`?(challenger|critic)-"; "i"))
      or ($d | test("^[ \t]*(the[ \t]+)?challenger\\b"; "i"))
    then "yes" else "no" end' 2>/dev/null)" || exit 0
[ "$is_challenger" = "yes" ] || exit 0

spawn_model="$(printf '%s' "$hook_input" | jq -r '(.tool_input.model // "") | tostring | ascii_downcase' 2>/dev/null)" || exit 0

case "$spawn_model" in
  *opus*|*fable*) exit 0 ;;
esac

if [ -z "$spawn_model" ]; then
  shown="no model (it would inherit the session model)"
else
  shown="model '$spawn_model'"
fi
reason="Bureau reviewer floor: this Challenger spawn has $shown. The Challenger never runs below strong, even under quota pressure (config/model-policy.v2.json roles.challenger, issues #133 and #135). Respawn it with model: opus (or fable if routing escalated it). If the quota cannot cover an opus Challenger, stop and raise a checkpoint instead of reviewing on a cheaper model."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
