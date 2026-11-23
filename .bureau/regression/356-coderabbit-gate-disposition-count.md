name: coderabbit-gate clears findings only when a CODERABBIT-EVENT for the head dispositions at least as many as are open
phase: bug-fix (run 20261122-gate-surface-gaps, issue #146 item 2)
owner: scripts/coderabbit-gate.sh; docs/github-delivery.md (CODERABBIT-EVENT contract)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  OTHER=dddddddddddddddddddddddddddddddddddddddd
  printf 'Reviewing files that changed from the base of the PR and between %s and %s.\nActionable comments posted: 10\n' "$BASE" "$HEAD" > "$TMPF/c.txt"
  ev() { printf 'CODERABBIT-EVENT: {"head":"%s","findings":%s,"disposition":"addressed","note":"%s"}\n' "$1" "$2" "$3"; }
  run() { bash "$G" --comments-file "$TMPF/c.txt" --head "$HEAD" --inline-count 10 --log "$1" 2>&1; }
  want() {
    out=$(run "$2"); rc=$?
    [ "$rc" -eq "$3" ] || { echo "FAIL: $1 want rc=$3 got rc=$rc: $out"; exit 1; }
  }

  # N1: 7 of 10 dispositioned -> 3 still open -> fail, and say so.
  ev "$HEAD" 7 "seven fixed" > "$TMPF/n1.md"
  want "N1 7-of-10" "$TMPF/n1.md" 1
  printf '%s' "$out" | grep -q '7 of 10' || { echo "FAIL: N1 should report 7 of 10: $out"; exit 1; }

  # N2: the same 7-finding line logged twice (a replay) must not add up to 14.
  { ev "$HEAD" 7 "seven fixed"; ev "$HEAD" 7 "seven fixed"; } > "$TMPF/n2.md"
  want "N2 duplicated 7" "$TMPF/n2.md" 1

  # N3: 10 of 10 dispositioned -> pass.
  ev "$HEAD" 10 "all ten" > "$TMPF/n3.md"
  want "N3 10-of-10" "$TMPF/n3.md" 0

  # N4: cumulative later event (7 then 10) for the head -> pass on the max.
  { ev "$HEAD" 7 "seven"; ev "$HEAD" 10 "rest done"; } > "$TMPF/n4.md"
  want "N4 cumulative 7 then 10" "$TMPF/n4.md" 0

  # N5: a full disposition for ANOTHER head does not count here.
  ev "$OTHER" 10 "other head" > "$TMPF/n5.md"
  want "N5 other head" "$TMPF/n5.md" 1

  # N6: non-numeric findings never clears.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":"10","disposition":"addressed"}\n' "$HEAD" > "$TMPF/n6.md"
  want "N6 string findings" "$TMPF/n6.md" 1
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":"all","disposition":"addressed"}\n' "$HEAD" > "$TMPF/n6b.md"
  want "N6b word findings" "$TMPF/n6b.md" 1

  # N7: findings absent -> never clears.
  printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"overruled","note":"no count"}\n' "$HEAD" > "$TMPF/n7.md"
  want "N7 no findings field" "$TMPF/n7.md" 1

  # N8: the head sha appearing only inside a note does not count as the event's head.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":10,"note":"\\"head\\":\\"%s\\""}\n' "$OTHER" "$HEAD" > "$TMPF/n8.md"
  want "N8 head only in note" "$TMPF/n8.md" 1

  echo PASS
expected: exit 0; stdout "PASS". With 10 open findings, an event for the head with findings 7 fails and names "7 of 10" (N1); the same 7-line logged twice still fails (N2, max not sum); 10 passes (N3); 7 then 10 passes on the max (N4); an event for another head fails (N5); string, word, or missing findings never clear (N6, N6b, N7); the head sha quoted inside a note of another head's event does not count (N8). Mutation: revert to the any-line `"head":"<sha>"` grep → N1 passes and the fixture fails.
