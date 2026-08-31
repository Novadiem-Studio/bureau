name: GitHub delivery blocks local merge and records an honest issue-to-PR lifecycle
phase: GitHub-native delivery
owner: scripts/run-worktree.sh + scripts/pr-delivery.sh
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

  if "$ROOT/scripts/run-worktree.sh" merge --run-dir "$RUN" >"$TMPF/merge.out" 2>&1; then
    echo "local merge unexpectedly allowed"
    exit 1
  fi
  grep -Fq 'local merge disabled' "$TMPF/merge.out" || exit 1

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
    "pr merge") exit 0 ;;
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
  git -C "$WT" commit -m "fix: make command pass" -m "Co-authored-by: Ada Lovelace <ada@example.com>" >/dev/null || exit 1
  SHA=$(git -C "$WT" rev-parse HEAD)
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" coauthor \
    --run-dir "$RUN" --name "Ada Lovelace" --email "ada@example.com" \
    --commit "$SHA" --confirmed-human >/dev/null || exit 1

  cat > "$RUN/github/evidence.md" <<'EVIDENCE'
  ## Problem and intended result

  The failing command now passes.

  ## Important architectural decisions

  - Kept the change at the existing seam.

  ## Testing performed

  - Regression command passed.

  ## Screenshots

  - Not applicable: command-line behavior.

  ## Risks

  - Low; one bounded path changed.

  ## Rollback

  - Revert the merged pull request.

  ## Bureau cold review

  - Accepted.

  ## Objection resolution

  - No blockers were raised.
  EVIDENCE
  printf '%s\n' 'Cold review accepted; no blockers.' > "$RUN/github/cold-review.md"

  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" review \
    --run-dir "$RUN" --review-summary "$RUN/github/cold-review.md" \
    --verdict accepted >/dev/null || exit 1
  GH_ACTOR=ada PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" review \
    --run-dir "$RUN" --review-summary "$RUN/github/cold-review.md" \
    --verdict accepted >/dev/null || exit 1
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" ready --run-dir "$RUN" >/dev/null || exit 1
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" merge \
    --run-dir "$RUN" >/dev/null || exit 1
  "$ROOT/scripts/run-worktree.sh" remove --run-dir "$RUN" >/dev/null || exit 1

  jq -e --arg sha "$SHA" '
    .git.delivery_mode == "github"
    and .git.issue_number == 12
    and .git.pr_number == 34
    and .git.pr_is_draft == false
    and .git.cold_review_status == "accepted"
    and .git.cold_review_mode == "approval"
    and .git.status == "removed"
    and (.git.coauthors == [{name:"Ada Lovelace",email:"ada@example.com",commit:$sha}])
  ' "$RUN/state.json" >/dev/null || exit 1
  grep -Fq 'Fixes #12' "$RUN/github/pr-body.md" || exit 1
  grep -Fq 'pr create --repo acme/demo --draft' "$GH_LOG" || exit 1
  grep -Fq 'pr comment 34 --repo acme/demo' "$GH_LOG" || exit 1
  grep -Fq 'pr review 34 --repo acme/demo --approve' "$GH_LOG" || exit 1
  [ "$(grep -Fc 'pr review 34' "$GH_LOG")" -eq 1 ] || exit 1
  grep -Fq 'pr ready 34 --repo acme/demo' "$GH_LOG" || exit 1
  grep -Fq 'pr merge 34 --repo acme/demo --merge' "$GH_LOG" || exit 1
  [ ! -d "$WT" ] || exit 1
  if git -C "$REPO" show-ref --verify --quiet refs/heads/bureau/run; then exit 1; fi
  PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$RUN" >/dev/null || exit 1
  echo PASS
expected: exit 0; stdout "PASS"; explicit GitHub delivery cannot local-merge, issue/early draft PR evidence is recorded, self cold review stays a comment while a separate collaborator can approve, genuine co-author provenance is verified, and the default regular merge goes through GitHub while preserving branch commits
