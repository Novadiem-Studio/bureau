name: coderabbit-gate accepts a formal CodeRabbit review on the head when the summary comment reports no range
phase: bug-fix (run 20261122-gate-surface-gaps, issue #146 item 3)
owner: scripts/coderabbit-gate.sh (--reviews-file seam; live path gh api pulls/{n}/reviews)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  OTHER=cccccccccccccccccccccccccccccccccccccccc
  # A paused summary: the bot commented but reported no reviewed range.
  printf '<!-- This is an auto-generated comment: review paused by coderabbit.ai -->\nAuto reviews are paused on this PR. Use @coderabbitai resume.\n' > "$TMPF/p.txt"
  rv() { printf '[{"id":1,"user":{"login":"%s"},"commit_id":"%s","state":"COMMENTED"}]\n' "$1" "$2"; }
  run() { bash "$G" --comments-file "$TMPF/p.txt" --head "$HEAD" --inline-count 0 ${1:+--reviews-file "$1"} 2>&1; }
  want() {
    out=$(run "$2"); rc=$?
    [ "$rc" -eq "$3" ] || { echo "FAIL: $1 want rc=$3 got rc=$rc: $out"; exit 1; }
  }

  # V1: a coderabbitai[bot] review whose commit_id is the head -> reviewed, pass.
  rv 'coderabbitai[bot]' "$HEAD" > "$TMPF/v1.json"
  want "V1 bot review on head" "$TMPF/v1.json" 0

  # V2: the bot's review is of a different commit -> still unreviewed.
  rv 'coderabbitai[bot]' "$OTHER" > "$TMPF/v2.json"
  want "V2 bot review on other commit" "$TMPF/v2.json" 1

  # V3: a review on the head by another login does not count.
  rv 'someone' "$HEAD" > "$TMPF/v3.json"
  want "V3 other login on head" "$TMPF/v3.json" 1

  # V4: an empty reviews list -> still unreviewed.
  printf '[]\n' > "$TMPF/v4.json"
  want "V4 no reviews" "$TMPF/v4.json" 1

  # V5: no --reviews-file at all (the default is []) -> still unreviewed.
  want "V5 flag omitted" "" 1
  printf '%s' "$out" | grep -q 'never reported a reviewed commit range' \
    || { echo "FAIL: V5 should keep the no-range defect: $out"; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS". With a paused summary comment (no "between <base> and <head>" range), a reviews entry from coderabbitai[bot] whose commit_id equals the head passes (V1); one on another commit (V2), one by another login (V3), an empty list (V4) or no --reviews-file (V5) all fail. Mutation: delete the reviews branch in scripts/coderabbit-gate.sh → V1 fails.
