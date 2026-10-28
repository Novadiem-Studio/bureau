name: F317 · terminal-pairing.sh does not count an absent gate as red, but refuses to pair when every gate is absent (issue #115)
phase: 115 · integration gate regression runner resolution
owner: scripts/terminal-pairing.sh — gate colour check
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
  SHA=0123456789abcdef0123456789abcdef01234567
  ABSENT='{"name":"regression","command":"(absent)","exit_code_branch":null,"result":"absent"}'
  GREEN='{"name":"npm-test","command":"npm run test","exit_code_branch":0,"result":"green"}'
  mk() { printf '{"escalate_marker":"","final_gate":true,"gate_mode":"local","branch_tip":"%s","fast_forward_ok":true,"conflicts_clean":true,"gates":[%s]}\n' "$SHA" "$1" > "$TMPD/g.json"; }
  # Absent beside a green gate pairs.
  mk "$ABSENT,$GREEN"
  out=$(sh "$ROOT/scripts/terminal-pairing.sh" --gate "$TMPD/g.json" --review-sha "$SHA" 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: absent+green exited $rc (expected 0 paired): $out"; exit 1; }
  # Every gate absent: discard, and the reason says no gate ran (not "red gate").
  mk "$ABSENT"
  out=$(sh "$ROOT/scripts/terminal-pairing.sh" --gate "$TMPD/g.json" --review-sha "$SHA" 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: all-absent exited $rc (expected 1 discard): $out"; exit 1; }
  printf '%s\n' "$out" | grep -q "no gate ran (every gate absent" || { echo "FAIL: expected every-gate-absent reason: $out"; exit 1; }
  if printf '%s\n' "$out" | grep -q "red gate"; then echo "FAIL: absent reported as red: $out"; exit 1; fi
  # A record marked absent that carries an exit code is judged on that code.
  mk '{"name":"regression","command":"x","exit_code_branch":1,"result":"absent"},'"$GREEN"
  out=$(sh "$ROOT/scripts/terminal-pairing.sh" --gate "$TMPD/g.json" --review-sha "$SHA" 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: absent with exit 1 exited $rc (expected 1 discard): $out"; exit 1; }
  echo "PASS"
  # Mutation note: restore the old check (exit_code_branch != 0 or result != green
  # is red). The absent+green case then discards as "red gate(s): regression" with
  # exit 1, failing the first assertion.
expected: PASS
