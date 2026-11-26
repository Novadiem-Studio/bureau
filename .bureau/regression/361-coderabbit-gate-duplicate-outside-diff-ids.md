name: coderabbit-gate gives every duplicate outside-diff entry of one review its own stable id, keeping the legacy id for the first
phase: bug-fix (run 20261124-gate-edges-149, issue #149 item 2)
owner: scripts/coderabbit-gate.sh (body-only finding ids); docs/github-delivery.md (CodeRabbit id rule)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PATH=/usr/bin:/bin:$PATH
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=1111111111111111111111111111111111111111
  BASE=2222222222222222222222222222222222222222
  printf 'Reviewed between %s and %s\n' "$BASE" "$HEAD" > "$TMPF/c.txt"
  echo '[]' > "$TMPF/inline.json"
  # The legacy id of ("a.sh:1-2", "Same title") in review 900: b900- + 12 hex of sha256("a.sh:1-2|Same title").
  LEGACY=b900-2f6ed1df2cc4
  # rv <n>: one bot review (id 900) on the head whose outside-diff section lists the same
  # loc and title n times.
  rv() {
    { printf '**Actionable comments posted: 0**\n\n> **Outside diff range comments (%s)**\n' "$1"
      i=0; while [ "$i" -lt "$1" ]; do printf '> <summary><strong>Major</strong> \302\267 Same title \302\267 <code>a.sh:1-2</code></summary>\n'; i=$((i + 1)); done
    } | jq -Rs --arg c "$HEAD" '[{id:900,user:{login:"coderabbitai[bot]"},commit_id:$c,state:"COMMENTED",body:.}]'
  }
  ev() { printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"addressed","ids":[%s],"note":"n"}\n' "$HEAD" "$1"; }
  run() { out=$(bash "$G" --comments-file "$TMPF/c.txt" --head "$HEAD" --inline-file "$TMPF/inline.json" --reviews-file "$1" ${2:+--log "$2"} 2>&1); rc=$?; }
  ids() { printf '%s' "$out" | grep -oE 'open: [^)]*' | head -1 | grep -oE 'b900-[0-9a-f]{12}' | sort -u; }

  # D0: one entry keeps the legacy id (dispositions already logged still match).
  rv 1 > "$TMPF/r1.json"
  run "$TMPF/r1.json"
  [ "$rc" -eq 1 ] && [ "$(ids)" = "$LEGACY" ] || { echo "FAIL: D0 single entry should be open as $LEGACY: $out"; exit 1; }
  # D1: two identical entries are two open findings with two distinct ids; the first is the legacy id.
  rv 2 > "$TMPF/r2.json"
  run "$TMPF/r2.json"
  IDS=$(ids)
  [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$IDS" | grep -c .)" -eq 2 ] || { echo "FAIL: D1 want 2 distinct open ids: $out"; exit 1; }
  printf '%s\n' "$IDS" | grep -Fxq "$LEGACY" || { echo "FAIL: D1 first duplicate lost the legacy id: $out"; exit 1; }
  printf '%s' "$out" | grep -Fq 'has 2 of 2 finding(s)' || { echo "FAIL: D1 count message: $out"; exit 1; }
  # D2: the ids are stable across a re-fetch of the same review.
  run "$TMPF/r2.json"
  [ "$(ids)" = "$IDS" ] || { echo "FAIL: D2 ids not stable"; exit 1; }
  # D3: naming only the legacy id leaves the second duplicate open.
  ev "\"$LEGACY\"" > "$TMPF/d3.md"
  run "$TMPF/r2.json" "$TMPF/d3.md"
  OTHER=$(printf '%s\n' "$IDS" | grep -Fxv "$LEGACY")
  [ "$rc" -eq 1 ] && [ "$(ids)" = "$OTHER" ] || { echo "FAIL: D3 one disposition must not clear both: rc=$rc $out"; exit 1; }
  printf '%s' "$out" | grep -Fq 'has 1 of 2 finding(s)' || { echo "FAIL: D3 count message: $out"; exit 1; }
  # D4: naming both passes.
  ev "\"$LEGACY\",\"$OTHER\"" > "$TMPF/d4.md"
  run "$TMPF/r2.json" "$TMPF/d4.md"
  [ "$rc" -eq 0 ] || { echo "FAIL: D4 both named should pass: $out"; exit 1; }
  # D5: three duplicates are three distinct ids, the first two as in D1.
  rv 3 > "$TMPF/r3.json"
  run "$TMPF/r3.json"
  I3=$(ids)
  [ "$(printf '%s\n' "$I3" | grep -c .)" -eq 3 ] || { echo "FAIL: D5 want 3 distinct ids: $out"; exit 1; }
  for i in $IDS; do printf '%s\n' "$I3" | grep -Fxq "$i" || { echo "FAIL: D5 id $i changed when a third duplicate appeared"; exit 1; }; done
  # D6: the ordinal counts repeats of one file:lines and title, not entries in the list: an
  # entry sharing only the file:lines, only the title, or neither keeps the id it has alone.
  # rl <loc|title>...: one bot review (id 900) on the head listing those entries in order.
  rl() {
    { printf '> **Outside diff range comments (%s)**\n' "$#"
      for e in "$@"; do printf '> <summary><strong>Major</strong> \302\267 %s \302\267 <code>%s</code></summary>\n' "${e#*|}" "${e%%|*}"; done
    } | jq -Rs --arg c "$HEAD" '[{id:900,user:{login:"coderabbitai[bot]"},commit_id:$c,state:"COMMENTED",body:.}]'
  }
  want=""
  for e in 'a.sh:1-2|Same title' 'a.sh:1-2|Other title' 'b.sh:1-2|Same title' 'c.sh:9|Third'; do
    rl "$e" > "$TMPF/r6.json"; run "$TMPF/r6.json"; want="$want$(ids)
  "
  done
  rl 'a.sh:1-2|Same title' 'a.sh:1-2|Other title' 'b.sh:1-2|Same title' 'c.sh:9|Third' > "$TMPF/r6.json"
  run "$TMPF/r6.json"
  want=$(printf '%s' "$want" | tr -d ' ' | grep . | sort -u)
  [ "$(printf '%s\n' "$want" | grep -c .)" -eq 4 ] && [ "$(ids)" = "$want" ] || { echo "FAIL: D6 want each entry's own id ($want): $out"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". A review on the head whose "Outside diff range comments" section lists the same file:lines and title more than once gets one id per entry: the first keeps the legacy id b900-2f6ed1df2cc4 (D0, D1), later ones get their own id in the b<digits>-<hex> grammar, stable across re-fetches (D2) and when more duplicates appear (D5); naming one id leaves the other open with a "1 of 2" count (D3), naming both passes (D4). The ordinal counts repeats of one file:lines and title, so entries that share only one of them, or neither, each keep the id they have alone (D6). Mutations in coderabbit-gate.sh: drop the ordinal from the hash input and D1 fails (one id for two findings); count it over the whole list, or per file:lines only, or per title only, and D6 fails.
