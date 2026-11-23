name: coderabbit-gate live inline-comment lookup sums paginated counts and fails loudly when the request fails
phase: bug-fix (run 20261122-gate-surface-gaps, issue #146 CodeRabbit round 2, findings D and E)
owner: scripts/coderabbit-gate.sh (live `gh api repos/$REPO/pulls/$PR/comments --paginate` path)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  BIN="$TMPF/bin"; mkdir -p "$BIN"
  export HEAD BASE
  # Stub gh: the live path with --paginate --jq prints one jq result per page.
  cat > "$BIN/gh" <<'FAKEGH'
  #!/bin/sh
  case "$1 $2" in
    "pr view") printf '{"headRefOid":"%s","isDraft":false,"state":"OPEN","url":"u"}\n' "$HEAD" ;;
    "api repos/acme/demo/issues/7/comments") printf 'Reviewing files that changed from the base of the PR and between %s and %s.\n' "$BASE" "$HEAD" ;;
    "api repos/acme/demo/pulls/7/comments")
      # The live --jq emits one bot comment id per line, across all pages.
      case "$INLINE_MODE" in
        pages) i=1; while [ $i -le 31 ]; do echo $((1000 + i)); i=$((i + 1)); done ;;
        empty) : ;;
        fail)  echo 'HTTP 502: Bad Gateway' >&2; exit 1 ;;
      esac ;;
    "api repos/acme/demo/pulls/7/reviews")
      [ "$REVIEWS_MODE" = fail ] && { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
      : ;;
    *) printf 'unexpected fake gh call: %s\n' "$*" >&2; exit 9 ;;
  esac
  FAKEGH
  chmod +x "$BIN/gh"
  run() { INLINE_MODE="$1" REVIEWS_MODE="${REVIEWS_MODE:-ok}" PATH="$BIN:$PATH" bash "$G" --repo acme/demo --pr 7 ${2:+--log "$2"} 2>&1; }
  want() {
    out=$(run "$2" "$3"); rc=$?
    [ "$rc" -eq "$4" ] || { echo "FAIL: $1 want rc=$4 got rc=$rc: $out"; exit 1; }
  }
  # Name ids 1001..1000+N in one event.
  ev() { ids=$(i=1; while [ $i -le "$1" ]; do printf '%s%s' "${sep:-}" $((1000 + i)); sep=,; i=$((i + 1)); done); printf 'CODERABBIT-EVENT: {"head":"%s","disposition":"addressed","ids":[%s]}\n' "$HEAD" "$ids"; }

  # E1: ids from both pages (30 + 1) are all open; naming the first 30 leaves 1031 open.
  ev 30 > "$TMPF/e1.md"
  want "E1 paginated, 30 of 31 named" pages "$TMPF/e1.md" 1
  printf '%s' "$out" | grep -q 'open: 1031' || { echo "FAIL: E1 should list 1031 as open: $out"; exit 1; }
  # E2: naming all 31 clears them.
  ev 31 > "$TMPF/e2.md"
  want "E2 paginated, all 31 named" pages "$TMPF/e2.md" 0

  # D1: the inline lookup failing is an error, not zero findings.
  want "D1 lookup fails" fail "" 2
  printf '%s' "$out" | grep -q 'inline review comments' || { echo "FAIL: D1 should name the failed lookup: $out"; exit 1; }
  printf '%s' "$out" | grep -q 'coderabbit: clean' && { echo "FAIL: D1 must not report clean: $out"; exit 1; }
  # D2: a successful empty response is no findings and passes.
  want "D2 empty success" empty "" 0
  # D3: the reviews lookup failing is an error too (body-only findings live there).
  REVIEWS_MODE=fail want "D3 reviews lookup fails" empty "" 2
  printf '%s' "$out" | grep -q 'formal reviews' || { echo "FAIL: D3 should name the failed lookup: $out"; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS". With a stubbed gh on the live path, bot inline comment ids from every page are open findings, so naming 30 of 31 fails and lists 1031 (E1) and naming all 31 passes (E2); a failing pulls/comments request exits 2 naming the inline lookup and never prints "clean" (D1); a successful empty response is no findings and passes (D2); a failing pulls/reviews request exits 2 (D3). Mutation: drop the exit-status check on the inline lookup → D1 fails; on the reviews lookup → D3 fails. (Round 2's per-page count sum is gone with the count rule; ids need no summing.)
