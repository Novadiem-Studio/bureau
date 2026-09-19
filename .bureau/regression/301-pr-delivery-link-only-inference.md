name: pr-delivery.sh infers link-only vs. closing-keyword issue linking from branch content, honors an explicit override across refresh, and fails closed when GitHub still reports a closing reference
phase: GitHub-native delivery
owner: scripts/pr-delivery.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM

  ORIGIN="$TMPF/origin.git"
  REPO="$TMPF/repo"
  BIN="$TMPF/bin"
  GH_LOG="$TMPF/gh.log"
  export GH_LOG
  mkdir -p "$BIN"

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

  cat > "$BIN/gh" <<'FAKEGH'
  #!/bin/sh
  printf '%s\n' "$*" >> "$GH_LOG"
  ISSUE_NUM="${FAKE_ISSUE_NUM:-12}"
  PR_NUM="${FAKE_PR_NUM:-34}"
  CLOSING_COUNT="${FAKE_CLOSING_COUNT:-0}"
  case "$1 $2" in
    "repo view")
      case "$*" in
        *"--jq .nameWithOwner"*) printf '%s\n' 'acme/demo' ;;
        *) printf '%s\n' '{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo","visibility":"PUBLIC"}' ;;
      esac ;;
    "issue create") printf 'https://github.com/acme/demo/issues/%s\n' "$ISSUE_NUM" ;;
    "issue view") printf '{"number":%s,"url":"https://github.com/acme/demo/issues/%s","title":"Real issue"}\n' "$ISSUE_NUM" "$ISSUE_NUM" ;;
    "pr create") printf 'https://github.com/acme/demo/pull/%s\n' "$PR_NUM" ;;
    "pr edit") exit 0 ;;
    "pr view")
      case "$*" in
        *"number,url,isDraft"*) printf '{"number":%s,"url":"https://github.com/acme/demo/pull/%s","isDraft":true}\n' "$PR_NUM" "$PR_NUM" ;;
        *) printf '{"number":%s,"url":"https://github.com/acme/demo/pull/%s","state":"OPEN","isDraft":false,"reviewDecision":"","mergeStateStatus":"CLEAN"}\n' "$PR_NUM" "$PR_NUM" ;;
      esac ;;
    "api graphql")
      if [ "${FAKE_GRAPHQL_FAIL:-0}" = "1" ]; then
        printf 'gh: GraphQL: rate limit exceeded\n' >&2
        exit 1
      fi
      printf '%s\n' "$CLOSING_COUNT" ;;
    "api user") printf '%s\n' "${GH_ACTOR:-robin}" ;;
    api*) printf '%s\n' '{}' ;;
    *) printf 'unexpected fake gh call: %s\n' "$*" >&2; exit 9 ;;
  esac
  FAKEGH
  chmod +x "$BIN/gh"

  new_run() {
    slug="$1"
    run_dir="$TMPF/$slug"
    wt_dir="$TMPF/wt-$slug"
    mkdir -p "$run_dir/github"
    cp "$ROOT/templates/state.json" "$run_dir/state.json"
    "$ROOT/scripts/run-worktree.sh" create --run-dir "$run_dir" --repo "$REPO" --base devel \
      --worktree-dir "$wt_dir" --delivery github >/dev/null || exit 1
    git -C "$wt_dir" config user.name "Robin"
    git -C "$wt_dir" config user.email "robin@example.com"
    printf 'Reproduce: run the command. Acceptance: it passes.\n' > "$run_dir/github/issue.md"
  }

  # A — no explicit flag, no code yet: open must reference the issue without closing it.
  new_run run-a
  FAKE_ISSUE_NUM=12 FAKE_PR_NUM=34 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$TMPF/run-a" --issue-title "Planning run" \
    --issue-body-file "$TMPF/run-a/github/issue.md" --title "Planning artifacts" >/dev/null || exit 1
  grep -Fq 'Planning artifacts for issue #12' "$TMPF/run-a/github/pr-body.md" \
    || { echo "FAIL A1: expected link-only body before any real commit"; exit 1; }
  grep -Fq 'Fixes #12' "$TMPF/run-a/github/pr-body.md" \
    && { echo "FAIL A1: must not contain the closing keyword yet"; exit 1; }

  # A continued — a real commit lands; refresh must flip the inference to closing.
  printf 'change\n' > "$TMPF/wt-run-a/change.txt"
  git -C "$TMPF/wt-run-a" add change.txt
  git -C "$TMPF/wt-run-a" commit -m "real work" >/dev/null || exit 1
  FAKE_ISSUE_NUM=12 FAKE_PR_NUM=34 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" refresh \
    --run-dir "$TMPF/run-a" >/dev/null || exit 1
  grep -Fq 'Fixes #12' "$TMPF/run-a/github/pr-body.md" \
    || { echo "FAIL A2: expected the closing keyword once a real commit lands"; exit 1; }

  # B — --link-only persists to state.json and survives a later real commit + refresh.
  new_run run-b
  FAKE_ISSUE_NUM=15 FAKE_PR_NUM=37 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$TMPF/run-b" --issue-title "Forced link-only" \
    --issue-body-file "$TMPF/run-b/github/issue.md" --title "Forced link-only PR" \
    --link-only >/dev/null || exit 1
  jq -e '.git.pr_link_mode == "link-only"' "$TMPF/run-b/state.json" >/dev/null \
    || { echo "FAIL B0: --link-only did not persist to state.json#git.pr_link_mode"; exit 1; }
  printf 'real change\n' > "$TMPF/wt-run-b/change.txt"
  git -C "$TMPF/wt-run-b" add change.txt
  git -C "$TMPF/wt-run-b" commit -m "real work despite forced link-only" >/dev/null || exit 1
  FAKE_ISSUE_NUM=15 FAKE_PR_NUM=37 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" refresh \
    --run-dir "$TMPF/run-b" >/dev/null || exit 1
  grep -Fq 'Planning artifacts for issue #15' "$TMPF/run-b/github/pr-body.md" \
    || { echo "FAIL B1: persisted --link-only must survive a refresh after real commits land"; exit 1; }
  grep -Fq 'Fixes #15' "$TMPF/run-b/github/pr-body.md" \
    && { echo "FAIL B1: persisted --link-only must not be overridden by inference"; exit 1; }

  # C — --closes-issue forces the closing keyword even with zero diff.
  new_run run-c
  FAKE_ISSUE_NUM=18 FAKE_PR_NUM=40 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$TMPF/run-c" --issue-title "Forced close" \
    --issue-body-file "$TMPF/run-c/github/issue.md" --title "Forced close PR" \
    --closes-issue >/dev/null || exit 1
  grep -Fq 'Fixes #18' "$TMPF/run-c/github/pr-body.md" \
    || { echo "FAIL C1: --closes-issue must force the closing keyword despite zero diff"; exit 1; }

  # D — GitHub's live GraphQL count is checked, not just the rendered body: if the API
  # still reports a closing reference on an (inferred) link-only PR, open fails closed.
  new_run run-d
  if FAKE_ISSUE_NUM=20 FAKE_PR_NUM=42 FAKE_CLOSING_COUNT=1 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$TMPF/run-d" --issue-title "Guard test" \
    --issue-body-file "$TMPF/run-d/github/issue.md" --title "Guard test PR" \
    >"$TMPF/guard.out" 2>&1
  then
    echo "FAIL D: open must fail when GraphQL still reports a closing reference on a link-only PR"
    cat "$TMPF/guard.out"
    exit 1
  fi
  grep -Fq 'still has 1 closing issue reference' "$TMPF/guard.out" \
    || { echo "FAIL D: expected the verify_link_mode die message"; cat "$TMPF/guard.out"; exit 1; }

  # E — an unverifiable GraphQL check (API error) must also fail closed, not be treated as
  # a pass: an unanswered safeguard is not a satisfied one.
  new_run run-e
  if FAKE_ISSUE_NUM=22 FAKE_PR_NUM=44 FAKE_GRAPHQL_FAIL=1 PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" open \
    --run-dir "$TMPF/run-e" --issue-title "API failure test" \
    --issue-body-file "$TMPF/run-e/github/issue.md" --title "API failure test PR" \
    >"$TMPF/guard-e.out" 2>&1
  then
    echo "FAIL E: open must fail closed when the GraphQL verification call itself errors"
    cat "$TMPF/guard-e.out"
    exit 1
  fi
  grep -Fq 'could not verify' "$TMPF/guard-e.out" \
    || { echo "FAIL E: expected the fail-closed die message for an unverifiable GraphQL check"; cat "$TMPF/guard-e.out"; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS". A — a fresh run with no explicit flag and no code yet opens with "Planning artifacts for issue #N" (never "Fixes #N"), and a later `refresh` after a real commit lands flips it to "Fixes #N". B — `--link-only` persists to `state.json#git.pr_link_mode` and survives a subsequent `refresh` even after real commits land (the explicit choice is not overridden by inference). C — `--closes-issue` forces the closing keyword even with zero diff. D — the helper checks GitHub's live `closingIssuesReferences` GraphQL count after writing the body and fails closed (rather than trusting the rendered text) when a link-only PR still shows a nonzero count. E — when the GraphQL verification call itself errors (rather than returning a count), `open` also fails closed instead of silently treating an unverifiable safeguard as satisfied. Mutation: revert `render_body`/`resolve_link_mode`/`branch_has_real_changes` to the unconditional `printf 'Fixes #%s\n\n' "$issue_number"` and cases A1, A1's negative check, B1, and B1's negative check all fail; delete the `verify_link_mode` call from `cmd_open` and case D wrongly passes (exit 0) instead of failing; revert `verify_link_mode`'s GraphQL-error branch to `|| return 0` and case E wrongly passes (exit 0) instead of failing.
