name: pr-delivery.sh ready refuses Pending, TBD and TODO in evidence and does not check angle brackets
phase: bug-fix (issue #158; replaces the code-span rows from issue #146 item 1)
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
  # R1: TBD as a word.
  printf '## Risks\n\n- TBD\n' > "$EV"
  must_fail "R1 TBD"
  # R2: the template's own placeholder line.
  printf '## Risks\n\n- Pending \342\200\224 replace before ready for review.\n' > "$EV"
  must_fail "R2 Pending dash"
  # R3: TODO as a word, here inside a code span (the scan reads the raw file).
  printf '## Testing performed\n\n- Ran `make test` and `TODO`.\n' > "$EV"
  must_fail "R3 TODO in a code span"
  # R4: an unreadable evidence file refuses instead of passing as clean. Skipped as root,
  # which reads the file anyway.
  if [ "$(id -u)" != 0 ]; then
    printf '## Risks\n\n- None.\n' > "$EV"; chmod 000 "$EV"
    if ready; then chmod 644 "$EV"; echo "FAIL: R4 unreadable evidence must refuse ready"; exit 1; fi
    chmod 644 "$EV"
    grep -Fq 'could not read' "$TMPF/out" || { echo "FAIL: R4 refused for another reason: $(cat "$TMPF/out")"; exit 1; }
  fi

  # P1: TBD and TODO inside longer words are not placeholders, and angle brackets pass
  # bare, in an inline span, after an unclosed backtick and in a fenced block (issue #158).
  printf '%s\n' '## Testing performed' '' '- Ran <the suite> and it passed; see `challenger-lens-s<k>-r<N>`.' \
    '- Ran `npm test and <x>.' '- Renamed TODOS.md and the mastodon TBDX flag.' '' '```' 'run --lens <k>' '```' > "$EV"
  must_pass "P1 angle brackets and longer words"

  echo PASS
expected: exit 0; stdout "PASS". cmd_ready refuses evidence holding TBD (R1), the template's "Pending —" line (R2), TODO even inside a code span (R3), or an evidence file it cannot read (R4), each with its own message. Evidence holding angle brackets anywhere, and TBD or TODO only inside longer words, passes (P1).
