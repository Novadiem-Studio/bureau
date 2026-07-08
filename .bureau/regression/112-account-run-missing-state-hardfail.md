name: account-run — missing state.json hard-fail: exits non-zero, names state.json in output, no accounting.json written
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  RP="$TMPF/06-no-state"
  mkdir -p "$RP"
  # deliberately no state.json
  out=$(bash "$ROOT/scripts/account-run.sh" "$RP" 2>&1) && { rm -rf "$TMPF"; exit 1; }
  # assert exit was non-zero AND output mentions state.json
  printf '%s\n' "$out" | grep -q 'state.json' || { rm -rf "$TMPF"; exit 1; }
  # assert no accounting.json was written
  [ ! -f "$RP/accounting.json" ] || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; script exits non-zero, output contains "state.json", no accounting.json written
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
