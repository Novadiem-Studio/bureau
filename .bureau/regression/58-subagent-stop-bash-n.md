name: subagent-stop bash -n syntax check — script is syntactically valid Bash
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  bash -n "$ROOT/scripts/subagent-stop.sh"
expected: exit 0, no output
phase: 02 · feature
owner: Prompt 2 / subagent-stop.sh
