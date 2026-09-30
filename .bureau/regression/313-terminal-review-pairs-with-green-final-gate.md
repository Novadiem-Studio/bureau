name: F313 · terminal-pairing.sh counts a parallel terminal review only with a green final gate on the same head SHA (issue #92)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PAIR="$ROOT/scripts/terminal-pairing.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  # results <file> <branch_tip> <final true|false> <gate result> <exit code> [escalate marker]
  results() {
    python3 - "$@" <<'PY'
  import json, sys
  path, tip, final, res, rc = sys.argv[1:6]
  marker = sys.argv[6] if len(sys.argv) > 6 else ""
  json.dump({"schema_version": 1, "checkpoint_type": "integration", "escalate_marker": marker,
             "final_gate": final == "true", "gate_mode": "ci", "branch_tip": tip,
             "ci": {"head_sha": tip, "status": "passed" if rc == "0" else "pending_timeout"},
             "gates": [{"name": "ci", "command": "gh pr checks 7", "exit_code_branch": int(rc), "result": res}],
             "fast_forward_ok": True, "conflicts_clean": True}, open(path, "w"))
  PY
  }
  expect() {  # <want exit> <label> <args...>
    want="$1"; label="$2"; shift 2
    set +e; out=$(sh "$PAIR" "$@" 2>&1); rc=$?; set -e
    [ "$rc" = "$want" ] || { echo "FAIL $label: exit $rc, want $want: $out"; exit 1; }
  }

  # Green final gate on A, review saw A => paired (0), record written.
  results "$TMP/green.json" "$A" true green 0
  expect 0 paired --gate "$TMP/green.json" --review-sha "$A" --out "$TMP/pair.json"
  jq -e --arg a "$A" '.status=="paired" and .paired==true and .gate_sha==$a and .review_sha==$a' "$TMP/pair.json" >/dev/null
  # Green final gate on A, review saw B => refused (3), both SHAs recorded.
  expect 3 mismatch --gate "$TMP/green.json" --review-sha "$B" --out "$TMP/mm.json"
  jq -e --arg a "$A" --arg b "$B" '.status=="refused" and .paired==false and .gate_sha==$a and .review_sha==$b' "$TMP/mm.json" >/dev/null
  # Red (pending-timeout) final gate on the same SHA => discard (1).
  results "$TMP/red.json" "$A" true red 124
  expect 1 red --gate "$TMP/red.json" --review-sha "$A" --out "$TMP/red-pair.json"
  jq -e '.status=="discard" and .paired==false and (.reason|test("red gate"))' "$TMP/red-pair.json" >/dev/null
  # A green gate that was not a final gate cannot pair a terminal review.
  results "$TMP/notfinal.json" "$A" false green 0
  expect 1 notfinal --gate "$TMP/notfinal.json" --review-sha "$A"
  # An escalate-marker gate cannot pair either.
  results "$TMP/esc.json" "$A" true green 0 "base-ref not resolvable"
  expect 1 escalate --gate "$TMP/esc.json" --review-sha "$A"
  # A short SHA is a usage error, not a prefix match.
  expect 2 shortsha --gate "$TMP/green.json" --review-sha aaaaaaaaaaaa
  echo PASS
expected: exit 0; stdout "PASS". A green final gate whose branch_tip equals the review SHA pairs (exit 0, record status "paired" with both SHAs). The same green gate against a review that saw a different SHA is refused (exit 3, status "refused", gate_sha and review_sha both recorded). A red final gate (pending timeout, exit 124) is a discard (exit 1). A green gate with final_gate false, or with an escalate marker, is a discard (exit 1). A 12-character SHA is a usage error (exit 2), never a prefix match. MUTATION - removing the `gate_sha != review_sha` refusal in scripts/terminal-pairing.sh makes the mismatch case exit 0; dropping the red-gate check makes the red case pair.
phase: 92 · parallel terminal review
owner: scripts/terminal-pairing.sh
