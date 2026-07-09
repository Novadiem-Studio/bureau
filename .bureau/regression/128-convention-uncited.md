name: C3 — convention-uncited positive fire (Check h hard gate)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  cat >"$WORK/spec.md" <<'SPECEOF'
  ## Architecture

  We add a database column `user_id` to track the originating identity.
  SPECEOF
  touch "$WORK/plan.md"
  output="$("$ROOT/scripts/preflight-artifacts.sh" "$WORK" --phase round1 2>&1)"
  status=$?
  echo "$output"
  echo "exit:$status"
  echo "$output" | grep -qF 'convention-uncited' || { echo "FAIL: convention-uncited not in output"; exit 1; }
  [ "$status" -eq 1 ] || { echo "FAIL: expected exit 1, got $status"; exit 1; }
  echo "PASS"
expected: |
  exit 0 (the fixture's own assertions passed)
  fixture stdout ends with: PASS
  script output contains convention-uncited and exit:1 appears in output
phase: Prompt 3 · feature (20260708-semantic-producer-checks)
owner: check_convention_citations — retire when Check h is removed or renamed
