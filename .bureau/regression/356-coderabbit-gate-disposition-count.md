name: coderabbit-gate clears findings only when every open finding id on the head is named in a CODERABBIT-EVENT for that head
phase: bug-fix (run 20261122-gate-surface-gaps, issue #146 item 2, reworked to per-id in round 3)
owner: scripts/coderabbit-gate.sh; docs/github-delivery.md (CODERABBIT-EVENT contract)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  OTHER=dddddddddddddddddddddddddddddddddddddddd
  # History: this fixture first pinned a count rule (max of `findings` >= open count).
  # Round 3 replaced it with per-id disposition, so its old rows are gone: "10 of 10
  # passes" and "7 then 10 passes" now contradict the contract (a count clears nothing,
  # S5), and the string/missing-count rows are subsumed by S5.
  printf 'Reviewing files that changed from the base of the PR and between %s and %s.\nActionable comments posted: 4\n' "$BASE" "$HEAD" > "$TMPF/c.txt"
  # Open inline findings: four top-level bot comments (the PR #148 ids). A bot reply and
  # a human comment are not findings.
  cat > "$TMPF/inline.json" <<'JSON'
  [{"id":4662945345,"user":{"login":"coderabbitai[bot]"},"in_reply_to_id":null},
   {"id":4662945353,"user":{"login":"coderabbitai[bot]"},"in_reply_to_id":null},
   {"id":4663583256,"user":{"login":"coderabbitai[bot]"},"in_reply_to_id":null},
   {"id":4663583272,"user":{"login":"coderabbitai[bot]"},"in_reply_to_id":null},
   {"id":999,"user":{"login":"coderabbitai[bot]"},"in_reply_to_id":4662945345},
   {"id":555,"user":{"login":"robin"},"in_reply_to_id":null}]
  JSON
  ALL='4662945345,4662945353,4663583256,4663583272'
  ev() { printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"%s","ids":[%s],"note":"n"}\n' "$1" "$2" "$3"; }
  run() { bash "$G" --comments-file "$TMPF/c.txt" --head "$HEAD" --inline-file "$TMPF/inline.json" ${2:+--reviews-file "$2"} --log "$1" 2>&1; }
  want() {
    out=$(run "$2" "$4"); rc=$?
    [ "$rc" -eq "$3" ] || { echo "FAIL: $1 want rc=$3 got rc=$rc: $out"; exit 1; }
  }
  open_list() { printf '%s' "$out" | grep -oE 'open: [^)]*' | head -1; }

  # S1: the silent pass the count rule allowed on 548488f. The event names 4 ids, one of
  # them open, and carries findings 4; the open set is 4. The count matches, but three
  # open findings are not named, so the gate fails and lists exactly those three.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":4,"disposition":"addressed","ids":[4662945345,"b1-aaaa","b1-bbbb","b1-cccc"],"note":"A,C,D,E"}\n' "$HEAD" > "$TMPF/s1.md"
  want "S1 count matches, ids do not" "$TMPF/s1.md" 1
  [ "$(open_list)" = "open: 4662945353 4663583256 4663583272" ] || { echo "FAIL: S1 open list: $out"; exit 1; }

  # S2: every open id named -> pass (the reply 999 and human 555 need no naming).
  ev "$HEAD" addressed "$ALL" > "$TMPF/s2.md"
  want "S2 all named" "$TMPF/s2.md" 0

  # S3: one open id missing -> fail listing only that id.
  ev "$HEAD" addressed '4662945345,4662945353,4663583256' > "$TMPF/s3.md"
  want "S3 one missing" "$TMPF/s3.md" 1
  [ "$(open_list)" = "open: 4663583272" ] || { echo "FAIL: S3 open list: $out"; exit 1; }

  # S4: all ids named, but for another head -> fail.
  ev "$OTHER" addressed "$ALL" > "$TMPF/s4.md"
  want "S4 other head" "$TMPF/s4.md" 1

  # S5: the old count-only shape clears nothing, whatever the total.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":99,"disposition":"addressed","note":"all"}\n' "$HEAD" > "$TMPF/s5.md"
  want "S5 count-only event" "$TMPF/s5.md" 1

  # S6: the same partial line logged twice clears nothing it does not name.
  { ev "$HEAD" addressed '4662945345,4662945353'; ev "$HEAD" addressed '4662945345,4662945353'; } > "$TMPF/s6.md"
  want "S6 duplicated partial" "$TMPF/s6.md" 1
  [ "$(open_list)" = "open: 4663583256 4663583272" ] || { echo "FAIL: S6 open list: $out"; exit 1; }

  # S7: ids may be strings or numbers, and may be split over several events -> pass.
  { ev "$HEAD" addressed '"4662945345",4662945353'; ev "$HEAD" overruled '"4663583256","4663583272"'; } > "$TMPF/s7.md"
  want "S7 split events, string ids" "$TMPF/s7.md" 0

  # S8: a disposition other than addressed|overruled clears nothing.
  ev "$HEAD" pending "$ALL" > "$TMPF/s8.md"
  want "S8 bad disposition" "$TMPF/s8.md" 1

  # S9: the head sha only inside a note of another head's event does not count.
  printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"addressed","ids":[%s],"note":"\\"head\\":\\"%s\\""}\n' "$OTHER" "$ALL" "$HEAD" > "$TMPF/s9.md"
  want "S9 head only in note" "$TMPF/s9.md" 1

  # S10: the summary claims 5 actionable comments but only 4 finding ids exist, and all 4
  # are named. Some finding cannot be named, so the gate fails closed (count guard).
  printf 'Reviewing files that changed from the base of the PR and between %s and %s.\nActionable comments posted: 5\n' "$BASE" "$HEAD" > "$TMPF/c5.txt"
  out=$(bash "$G" --comments-file "$TMPF/c5.txt" --head "$HEAD" --inline-file "$TMPF/inline.json" --log "$TMPF/s2.md" 2>&1); rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: S10 actionable above ids want rc=1 got rc=$rc: $out"; exit 1; }
  printf '%s' "$out" | grep -q 'but only 4 finding id(s) were found' || { echo "FAIL: S10 should say why: $out"; exit 1; }

  # Body-only findings: outside-diff comments in the head review's body, with no comment id.
  SUM='<summary><strong><picture><img src="https://x/major-16.svg" alt=""></picture> Major</strong> · %s · <code>%s</code></summary><blockquote>'
  body() {
    printf '**Actionable comments posted: 0**\n\n> [!CAUTION]\n> Some comments are outside the diff.\n> \n> **Outside diff range comments (%s)**\n> \n' "$1"
    printf "> <details>\n> $SUM\n> text\n> <details>\n> <summary><picture>p</picture> Prompt to fix issue</summary>\n> </details>\n> </blockquote></details>\n" 'Reject a failed request.' 'coderabbit-gate.sh:173-174'
    printf "> <details>\n> $SUM\n> text\n> </blockquote></details>\n" 'Sum the page counts.' 'coderabbit-gate.sh:173-174'
    printf '\n<details>\n<summary>Review details</summary>\n</details>\n'
  }
  rv() { body "$3" | jq -Rs --arg c "$2" --argjson id "$1" '[{id:$id,user:{login:"coderabbitai[bot]"},commit_id:$c,state:"COMMENTED",body:.}]'; }

  # B1: two body-only findings on the head review; inline all named, body ids not -> fail,
  # listing two derived ids, the same on a rerun. B2: naming them as well -> pass.
  rv 6017987303 "$HEAD" 2 > "$TMPF/r2.json"
  ev "$HEAD" addressed "$ALL" > "$TMPF/b1.md"
  want "B1 body ids open" "$TMPF/b1.md" 1 "$TMPF/r2.json"
  BIDS=$(printf '%s' "$out" | grep -oE 'b6017987303-[0-9a-f]{12}' | sort -u)
  [ "$(printf '%s\n' "$BIDS" | grep -c .)" -eq 2 ] || { echo "FAIL: B1 should list 2 derived body ids: $out"; exit 1; }
  out2=$(run "$TMPF/b1.md" "$TMPF/r2.json")
  [ "$(printf '%s' "$out2" | grep -oE 'b6017987303-[0-9a-f]{12}' | sort -u)" = "$BIDS" ] || { echo "FAIL: B1 derived ids not stable"; exit 1; }
  { ev "$HEAD" addressed "$ALL"; ev "$HEAD" overruled "$(printf '"%s",' $BIDS | sed 's/,$//')"; } > "$TMPF/b2.md"
  want "B2 body ids named" "$TMPF/b2.md" 0 "$TMPF/r2.json"

  # B3: the header says 3 but only 2 entries parse -> fail closed, even with all named.
  rv 6017987303 "$HEAD" 3 > "$TMPF/r3.json"
  want "B3 unparseable body" "$TMPF/b2.md" 1 "$TMPF/r3.json"
  printf '%s' "$out" | grep -q 'Outside diff range' || { echo "FAIL: B3 should say why: $out"; exit 1; }

  # B4: the same body on a review of another commit is not a finding on this head.
  rv 6017987303 "$OTHER" 2 > "$TMPF/r4.json"
  want "B4 body on other commit" "$TMPF/s2.md" 0 "$TMPF/r4.json"

  echo PASS
expected: exit 0; stdout "PASS". The open set is the top-level coderabbitai[bot] inline comment ids plus the ids derived from the head review's "Outside diff range comments (N)" entries. S1 (the 548488f silent pass: a count of 4 matching 4 open, three of them unnamed) fails and lists exactly 4662945353, 4663583256 and 4663583272. All named passes (S2, and split events with string ids, S7). One missing (S3), another head (S4), a count-only event (S5), a duplicated partial line (S6), a disposition other than addressed or overruled (S8), the head only inside a note (S9), and a summary claiming more actionable comments than there are ids even with every id named (S10) all fail. Body ids are listed and stable (B1), pass once named (B2), fail closed when the header count does not match the parsed entries (B3), and are not open when the review is of another commit (B4). Mutation: reinstate a count compare (event `findings` >= number of open ids clears) → S1 passes and the fixture fails.
Mutation: delete the `actionable -gt total+anon` block in scripts/coderabbit-gate.sh → S10 passes (rc 0) and the fixture fails.
