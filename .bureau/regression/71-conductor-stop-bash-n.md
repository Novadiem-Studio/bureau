name: conductor-stop bash -n syntax check — script is syntactically valid Bash
retired: 07 · execute-plan — FR4 REPLACE retired the live-hook token emission and baseline/delta lifecycle asserted here
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  bash -n "$ROOT/scripts/conductor-stop.sh"
expected: exit 0, no output
phase: 03 · feature
owner: Prompt 3 / conductor-stop.sh
