name: pr-delivery.sh ready ignores angle brackets inside code spans but still refuses real placeholders
phase: bug-fix (run 20261122-gate-surface-gaps, issue #146 item 1)
owner: scripts/pr-delivery.sh (cmd_ready placeholder lint)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM

  ORIGIN="$TMPF/origin.git"
  REPO="$TMPF/repo"
  RUN="$TMPF/run"
  WT="$TMPF/worktree"
  BIN="$TMPF/bin"
  GH_LOG="$TMPF/gh.log"
  export GH_LOG
  mkdir -p "$RUN" "$BIN"

  git init --bare "$ORIGIN" >/dev/null 2>&1 || exit 1
  git init "$REPO" >/dev/null 2>&1 || exit 1
  git -C "$REPO" config user.name "Robin"
  git -C "$REPO" config user.email "robin@example.com"
  printf 'seed\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -m seed >/dev/null || exit 1
  git -C "$REPO" branch -M devel
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -u origin devel >/dev/null 2>&1 || exit 1
  cp "$ROOT/templates/state.json" "$RUN/state.json"

  "$ROOT/scripts/run-worktree.sh" create \
    --run-dir "$RUN" --repo "$REPO" --base devel \
    --worktree-dir "$WT" --delivery github >/dev/null || exit 1
  git -C "$WT" config user.name "Robin"
  git -C "$WT" config user.email "robin@example.com"

  # Same stub gh as fixture 277.
  cat > "$BIN/gh" <<'FAKEGH'
  #!/bin/sh
  printf '%s\n' "$*" >> "$GH_LOG"
  case "$1 $2" in
    "repo view")
      case "$*" in
        *"--jq .nameWithOwner"*) printf '%s\n' 'acme/demo' ;;
        *) printf '%s\n' '{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo","visibility":"PUBLIC"}' ;;
      esac ;;
    "issue create") printf '%s\n' 'https://github.com/acme/demo/issues/12' ;;
    "issue view") printf '%s\n' '{"number":12,"url":"https://github.com/acme/demo/issues/12","title":"Real issue"}' ;;
    "pr create") printf '%s\n' 'https://github.com/acme/demo/pull/34' ;;
    "pr edit") exit 0 ;;
    "pr comment") printf '%s\n' 'https://github.com/acme/demo/pull/34#issuecomment-1' ;;
    "pr review") exit 0 ;;
    "pr ready") exit 0 ;;
    "api graphql") printf '%s\n' '0' ;;
    "pr view")
      case "$*" in
        *"--jq .author.login"*) printf '%s\n' 'robin' ;;
        *"number,url,isDraft"*) printf '%s\n' '{"number":34,"url":"https://github.com/acme/demo/pull/34","isDraft":true}' ;;
        *) printf '%s\n' '{"number":34,"url":"https://github.com/acme/demo/pull/34","state":"OPEN","isDraft":false,"reviewDecision":"","mergeStateStatus":"CLEAN"}' ;;
      esac ;;
    "api user") printf '%s\n' "${GH_ACTOR:-robin}" ;;
    api*) printf '%s\n' '{}' ;;
    *) printf 'unexpected fake gh call: %s\n' "$*" >&2; exit 9 ;;
  esac
  FAKEGH
  chmod +x "$BIN/gh"

  mkdir -p "$RUN/github"
  printf '%s\n' 'Reproduce: run the failing command. Acceptance: command passes.' > "$RUN/github/issue.md"
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$RUN" --issue-title "Real issue" \
    --issue-body-file "$RUN/github/issue.md" --title "Fix the real issue" \
    --summary "Make the failing command pass." >/dev/null || exit 1
  printf 'change\n' > "$WT/change.txt"
  git -C "$WT" add change.txt
  git -C "$WT" commit -m "fix: make command pass" >/dev/null || exit 1
  printf '%s\n' 'Cold review accepted; no blockers.' > "$RUN/github/cold-review.md"
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" review \
    --run-dir "$RUN" --review-summary "$RUN/github/cold-review.md" \
    --verdict accepted >/dev/null || exit 1

  EV="$RUN/github/evidence.md"
  ready() { PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" ready --run-dir "$RUN" >"$TMPF/out" 2>&1; }
  must_fail() {
    if ready; then echo "FAIL: $1 should be refused as a placeholder"; exit 1; fi
    grep -Fq 'placeholder text' "$TMPF/out" || { echo "FAIL: $1 refused for another reason: $(cat "$TMPF/out")"; exit 1; }
  }
  must_pass() { ready || { echo "FAIL: $1 should pass: $(cat "$TMPF/out")"; exit 1; }; }

  # Refusals first: each dies before ready changes state.
  # R1: a bare <placeholder> outside any code span.
  printf '## Testing performed\n\n- Ran <placeholder> and it passed.\n' > "$EV"
  must_fail "R1 bare <placeholder>"
  # R2: a <placeholder> after an unclosed backtick is not inside a span.
  printf '## Testing performed\n\n- Ran `npm test and <placeholder>.\n' > "$EV"
  must_fail "R2 unclosed backtick"
  # R3: TBD still fails, even inside a code span (only angle brackets skip spans).
  printf '## Risks\n\n- TBD\n' > "$EV"
  must_fail "R3 TBD"
  # R4: Pending dash still fails.
  printf '## Risks\n\n- Pending \342\200\224 waiting on review.\n' > "$EV"
  must_fail "R4 Pending dash"
  # R5: brackets in code are fine, but a bare one elsewhere in the same file still fails.
  printf '## Testing performed\n\n- Attempt ids look like `challenger-lens-s<k>-r<N>`.\n- Then <fill me in>.\n' > "$EV"
  must_fail "R5 mixed span and bare"

  # P1: angle brackets inside an inline code span (the issue #146 case).
  printf '## Testing performed\n\n- Attempt ids look like `challenger-lens-s<k>-r<N>`.\n- Ran ``a `<b>` c`` too.\n' > "$EV"
  must_pass "P1 inline code span"
  # P2: angle brackets inside a fenced block.
  printf '## Testing performed\n\n```\nscripts/run.sh --run-dir <RUN_DIR> --lens <k>\n```\n\n~~~sh\necho <x>\n~~~\n\nAll green.\n' > "$EV"
  must_pass "P2 fenced block"

  echo PASS
expected: exit 0; stdout "PASS". cmd_ready refuses evidence with a bare <placeholder> (R1), a <...> after an unclosed backtick (R2), TBD (R3), "Pending —" (R4), or a bare <...> next to a code span (R5), each with the "placeholder text" message; it accepts <...> inside inline code spans (P1) and fenced blocks (P2). Mutation: restore the raw-file `<[^>]+>` grep in cmd_ready → P1 is refused and the fixture fails.
