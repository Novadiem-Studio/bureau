name: coderabbit-gate reads "Actionable comments posted: N" from the bot's reviews on the head and fails closed when N exceeds the finding ids
phase: bug-fix (run 20261124-gate-edges-149, issue #149 item 4)
owner: scripts/coderabbit-gate.sh (actionable-count lower-bound guard); docs/github-delivery.md (CodeRabbit gate)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PATH=/usr/bin:/bin:$PATH
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=1111111111111111111111111111111111111111
  BASE=2222222222222222222222222222222222222222
  OLD=3333333333333333333333333333333333333333
  export HEAD BASE
  # The issue-comment surface carries the reviewed range only, as on live PR #148.
  printf 'Reviewed between %s and %s\n' "$BASE" "$HEAD" > "$TMPF/c.txt"
  printf '[{"id":4001,"user":{"login":"coderabbitai[bot]"}},{"id":4002,"user":{"login":"coderabbitai[bot]"}}]\n' > "$TMPF/inline.json"
  printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"addressed","ids":[4001,4002],"note":"n"}\n' "$HEAD" > "$TMPF/log.md"
  # rev <id> <commit> <login> <count line>: one formal review object (the live body shape).
  rev() { printf '<!-- coderabbit-ai-generated:v1 -->\n%s\n\n<details>\n<summary>Review details</summary>\n</details>\n' "$4" \
    | jq -Rs --argjson id "$1" --arg c "$2" --arg u "$3" '{id:$id,user:{login:$u},commit_id:$c,state:"COMMENTED",body:.}'; }
  run() { out=$(bash "$G" --comments-file "${2:-$TMPF/c.txt}" --head "$HEAD" --inline-file "$TMPF/inline.json" --reviews-file "$1" --log "$TMPF/log.md" 2>&1); rc=$?; }
  want() { [ "$rc" -eq "$2" ] || { echo "FAIL: $1 want rc=$2 got rc=$rc: $out"; exit 1; }; }

  # A1: the head review says 3, but only 2 ids exist (both named) -> fail closed, and say why.
  rev 10 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 3**' | jq -s . > "$TMPF/a1.json"
  run "$TMPF/a1.json"; want "A1 review count above ids" 1
  printf '%s' "$out" | grep -Fq 'reports 3 actionable comment(s)' || { echo "FAIL: A1 should name the count: $out"; exit 1; }
  # A2: a count equal to the ids passes (a lower bound, never an equality test).
  rev 10 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 2**' | jq -s . > "$TMPF/a2.json"
  run "$TMPF/a2.json"; want "A2 count equals ids" 0
  # A3: several head reviews carry a count -> the largest is used.
  { rev 10 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 1**'
    rev 11 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 3**'
    rev 12 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 2**'; } | jq -s . > "$TMPF/a3.json"
  run "$TMPF/a3.json"; want "A3 largest head count" 1
  # A4: a review on an older commit, or by another login, does not count.
  { rev 10 "$OLD" 'coderabbitai[bot]' '**Actionable comments posted: 9**'
    rev 11 "$HEAD" 'someone' '**Actionable comments posted: 9**'
    rev 12 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 1**'; } | jq -s . > "$TMPF/a4.json"
  run "$TMPF/a4.json"; want "A4 only bot reviews on the head" 0
  # A5: the bold-colon variant is read too.
  rev 10 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted:** 3' | jq -s . > "$TMPF/a5.json"
  run "$TMPF/a5.json"; want "A5 bold-colon variant" 1
  # A6: a head review with no count line is zero, not an error.
  rev 10 "$HEAD" 'coderabbitai[bot]' 'No actionable comments were generated.' | jq -s . > "$TMPF/a6.json"
  run "$TMPF/a6.json"; want "A6 no count line" 0
  # A7: the issue-comment count is still read; the larger of the two wins.
  printf 'Reviewed between %s and %s\nActionable comments posted: 3\n' "$BASE" "$HEAD" > "$TMPF/c3.txt"
  run "$TMPF/a2.json" "$TMPF/c3.txt"; want "A7 comment count larger than review count" 1

  # L1: the live path reads the count from GET pulls/N/reviews (one object per line with --paginate --jq '.[]').
  BIN="$TMPF/bin"; mkdir -p "$BIN"
  rev 10 "$HEAD" 'coderabbitai[bot]' '**Actionable comments posted: 3**' | jq -c . > "$TMPF/live-reviews.lines"
  export LIVE_REVIEWS="$TMPF/live-reviews.lines"
  printf '#!/bin/sh\ncase "$1 $2" in\n  "pr view") printf '"'"'{"headRefOid":"%%s","isDraft":false,"state":"OPEN","url":"u"}\\n'"'"' "$HEAD" ;;\n  "api repos/acme/demo/issues/7/comments") printf '"'"'Reviewed between %%s and %%s\\n'"'"' "$BASE" "$HEAD" ;;\n  "api repos/acme/demo/pulls/7/comments") echo 4001; echo 4002 ;;\n  "api repos/acme/demo/pulls/7/reviews") cat "$LIVE_REVIEWS" ;;\n  *) echo "unexpected fake gh call: $*" >&2; exit 9 ;;\nesac\n' > "$BIN/gh"
  chmod +x "$BIN/gh"
  out=$(PATH="$BIN:$PATH" bash "$G" --repo acme/demo --pr 7 --log "$TMPF/log.md" 2>&1); rc=$?
  want "L1 live review count above ids" 1
  printf '%s' "$out" | grep -Fq 'reports 3 actionable comment(s)' || { echo "FAIL: L1 should name the count: $out"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". The count guard reads "Actionable comments posted: N" (plain or bold, "**...: N**" or "**...:** N") from coderabbitai[bot] reviews whose commit_id is the head, taking the largest (A3), and still reads the issue-comment copy, taking the larger of the two (A7). With N above the finding ids it fails closed and names the count (A1, offline; L1, live path via a stub gh), equality passes (A2), older-commit or other-login reviews do not count (A4), the bold-colon variant is read (A5), and a review with no count line is zero (A6). Mutation: stop reading the review bodies (review_actionable forced to 0) in coderabbit-gate.sh and A1, A3, A5 and L1 fail.
