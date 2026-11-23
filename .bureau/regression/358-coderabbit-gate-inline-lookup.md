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
      case "$INLINE_MODE" in
        pages) printf '30\n1\n' ;;
        empty) printf '0\n' ;;
        fail)  echo 'HTTP 502: Bad Gateway' >&2; exit 1 ;;
      esac ;;
    "api repos/acme/demo/pulls/7/reviews") : ;;
    *) printf 'unexpected fake gh call: %s\n' "$*" >&2; exit 9 ;;
  esac
  FAKEGH
  chmod +x "$BIN/gh"
  run() { INLINE_MODE="$1" PATH="$BIN:$PATH" bash "$G" --repo acme/demo --pr 7 ${2:+--log "$2"} 2>&1; }
  want() {
    out=$(run "$2" "$3"); rc=$?
    [ "$rc" -eq "$4" ] || { echo "FAIL: $1 want rc=$4 got rc=$rc: $out"; exit 1; }
  }
  ev() { printf 'CODERABBIT-EVENT: {"head":"%s","findings":%s,"disposition":"addressed"}\n' "$HEAD" "$1"; }

  # E1: two pages of inline comments (30 + 1) are 31 findings; 30 dispositioned is not enough.
  ev 30 > "$TMPF/e1.md"
  want "E1 paginated 30+1 vs 30" pages "$TMPF/e1.md" 1
  printf '%s' "$out" | grep -q '30 of 31' || { echo "FAIL: E1 should report 30 of 31: $out"; exit 1; }
  # E2: 31 dispositioned clears the summed count.
  ev 31 > "$TMPF/e2.md"
  want "E2 paginated 30+1 vs 31" pages "$TMPF/e2.md" 0

  # D1: the inline lookup failing is an error, not zero findings.
  want "D1 lookup fails" fail "" 2
  printf '%s' "$out" | grep -q 'inline review comments' || { echo "FAIL: D1 should name the failed lookup: $out"; exit 1; }
  printf '%s' "$out" | grep -q 'coderabbit: clean' && { echo "FAIL: D1 must not report clean: $out"; exit 1; }
  # D2: a successful empty response stays 0 findings and passes.
  want "D2 empty success" empty "" 0

  echo PASS
expected: exit 0; stdout "PASS". With a stubbed gh on the live path, two pages of inline counts (30 and 1) are summed to 31, so a disposition of 30 fails with "30 of 31" (E1) and 31 passes (E2); a failing pulls/comments request exits 2 naming the inline lookup and never prints "clean" (D1); a successful empty response is 0 findings and passes (D2). Mutation: drop the per-page sum → E1 fails; drop the exit-status check → D1 fails.
