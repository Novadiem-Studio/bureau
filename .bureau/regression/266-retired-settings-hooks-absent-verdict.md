name: FR4 REPLACE settings gate accepts absent retired hooks and rejects either stale Bureau hook independently
owner: check-framework.sh retired Stop/SubagentStop settings verdict
phase: 06 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  HOME_DIR="$TMPF/home"
  SETTINGS="$HOME_DIR/.claude/settings.json"
  mkdir -p "$HOME_DIR/.claude"
  jq -n --arg status "$ROOT/scripts/statusline-usage.sh" \
    '{hooks:{},statusLine:{type:"command",command:$status}}' > "$SETTINGS"
  cp "$SETTINGS" "$TMPF/absent.json"

  if ! HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$ROOT/check-framework.sh" > "$TMPF/absent.out" 2>&1; then
    echo "FAIL: hooks-absent settings did not yield framework exit 0"
    tail -1 "$TMPF/absent.out"
    exit 1
  fi

  jq '.hooks.Stop=[{hooks:[{type:"command",command:"/Users/robin/Code/novadiem/bureau/scripts/conductor-stop.sh"}]}]' \
    "$TMPF/absent.json" > "$SETTINGS"
  if HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$ROOT/check-framework.sh" > "$TMPF/stop.out" 2>&1; then
    echo "FAIL: stale Stop hook did not make framework verdict non-zero"
    exit 1
  fi
  grep -Fq 'stale Stop hook remains wired to scripts/conductor-stop.sh' "$TMPF/stop.out" \
    || { echo "FAIL: stale Stop verdict diagnostic missing"; exit 1; }

  cp "$TMPF/absent.json" "$SETTINGS"
  jq '.hooks.SubagentStop=[{hooks:[{type:"command",command:"/Users/robin/Code/novadiem/bureau/scripts/subagent-stop.sh"}]}]' \
    "$TMPF/absent.json" > "$SETTINGS"
  if HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$ROOT/check-framework.sh" > "$TMPF/subagent.out" 2>&1; then
    echo "FAIL: stale SubagentStop hook did not make framework verdict non-zero"
    exit 1
  fi
  grep -Fq 'stale SubagentStop hook remains wired to scripts/subagent-stop.sh' "$TMPF/subagent.out" \
    || { echo "FAIL: stale SubagentStop verdict diagnostic missing"; exit 1; }

  cp "$TMPF/absent.json" "$SETTINGS"
  HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$ROOT/check-framework.sh" > "$TMPF/restored.out" 2>&1 \
    || { echo "FAIL: restored hooks-absent settings did not return framework to exit 0"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; hooks absent yields framework exit 0, independently restoring stale Bureau Stop or SubagentStop wiring yields non-zero with the matching diagnostic, and restoring the throwaway settings returns the verdict to green
