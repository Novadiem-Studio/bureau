#!/usr/bin/env bash
# GitHub-native delivery for Bureau worktree runs.
#
# Usage:
#   pr-delivery.sh open    --run-dir RUN_DIR (--issue NUMBER|URL | --issue-title TITLE --issue-body-file FILE) --title TITLE [--summary TEXT] [--github-repo OWNER/REPO] [--link-only|--closes-issue]
#   pr-delivery.sh refresh --run-dir RUN_DIR
#   pr-delivery.sh review  --run-dir RUN_DIR --review-summary FILE --verdict accepted|changes-requested [--inline-comments FILE]
#   pr-delivery.sh coauthor --run-dir RUN_DIR --name NAME --email EMAIL [--commit SHA] --confirmed-human
#   pr-delivery.sh ready   --run-dir RUN_DIR
#   pr-delivery.sh merge   --run-dir RUN_DIR [--merge-method merge|squash|rebase]
#   pr-delivery.sh status  --run-dir RUN_DIR
#
# --link-only renders "Planning artifacts for issue #N" instead of "Fixes #N", so merging the
# PR does not auto-close its tracking issue; --closes-issue forces the closing keyword. Either
# choice persists to state.json#git.pr_link_mode and is honored by every later refresh/ready/
# merge on this run — the caller does not need to remember to repeat it. With neither flag,
# the helper infers from the branch: zero diff against its base (e.g. only the empty
# "chore: start Bureau run" commit) means nothing was implemented, so it renders link-only;
# any real diff renders the closing keyword. The inference re-runs on every render, so a
# planning run that later gains real commits fixes itself on the next refresh.
#
# Public AND private repositories resolve auto delivery to GitHub (private default flipped
# to github 2026-09-09 per Robin: full issue/PR record everywhere). A repo opts back to local
# via state.json#git.private_delivery. Explicit github delivery fails closed.

set -euo pipefail

die() { echo "pr-delivery: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 required"; }

CMD="${1:-}"
[[ -n "$CMD" ]] || die "subcommand required: open | refresh | review | coauthor | ready | merge | status"
shift || true

RUN_DIR=""
ISSUE=""
ISSUE_TITLE=""
ISSUE_BODY_FILE=""
PR_TITLE=""
SUMMARY=""
REVIEW_SUMMARY=""
VERDICT=""
INLINE_COMMENTS=""
MERGE_METHOD="merge"
TARGET_GITHUB_REPO=""
LINK_MODE=""
COAUTHOR_NAME=""
COAUTHOR_EMAIL=""
COAUTHOR_COMMIT="HEAD"
CONFIRMED_HUMAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --issue-title) ISSUE_TITLE="$2"; shift 2 ;;
    --issue-body-file) ISSUE_BODY_FILE="$2"; shift 2 ;;
    --title) PR_TITLE="$2"; shift 2 ;;
    --summary) SUMMARY="$2"; shift 2 ;;
    --review-summary) REVIEW_SUMMARY="$2"; shift 2 ;;
    --verdict) VERDICT="$2"; shift 2 ;;
    --inline-comments) INLINE_COMMENTS="$2"; shift 2 ;;
    --merge-method) MERGE_METHOD="$2"; shift 2 ;;
    --github-repo) TARGET_GITHUB_REPO="$2"; shift 2 ;;
    --link-only) LINK_MODE="link-only"; shift ;;
    --closes-issue) LINK_MODE="close"; shift ;;
    --name) COAUTHOR_NAME="$2"; shift 2 ;;
    --email) COAUTHOR_EMAIL="$2"; shift 2 ;;
    --commit) COAUTHOR_COMMIT="$2"; shift 2 ;;
    --confirmed-human) CONFIRMED_HUMAN=1; shift ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

need_cmd git
need_cmd jq
[[ -n "$RUN_DIR" ]] || die "--run-dir required"
[[ -f "$RUN_DIR/state.json" ]] || die "state.json not found in $RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
STATE="$RUN_DIR/state.json"

read_git_state() { jq -c '.git // {}' "$STATE"; }

write_git_state() {
  local git_json="$1" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/bureau-pr-state.XXXXXX")"
  jq --argjson git "$git_json" '.git = $git | .last_updated = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' "$STATE" >"$tmp"
  mv "$tmp" "$STATE"
}

git_state="$(read_git_state)"
[[ "$(jq -r '.enabled // false' <<<"$git_state")" == "true" ]] || die "no active worktree recorded in state.json"
WORKTREE="$(jq -r '.worktree_path' <<<"$git_state")"
BRANCH="$(jq -r '.branch' <<<"$git_state")"
BASE="$(jq -r '.base_branch' <<<"$git_state")"
RUN_SLUG="$(jq -r '.run_slug' <<<"$git_state")"

require_worktree() { [[ -d "$WORKTREE" ]] || die "worktree missing: $WORKTREE"; }

update_state() {
  git_state="$1"
  write_git_state "$git_state"
}

resolve_delivery() {
  require_worktree
  local policy private_policy metadata visibility fallback origin_url github_remote
  policy="$(jq -r '.delivery_policy // "auto"' <<<"$git_state")"
  private_policy="$(jq -r '.private_delivery // "github"' <<<"$git_state")"
  if [[ "$policy" == "local" ]]; then
    update_state "$(jq '.delivery_mode = "local" | .delivery_fallback_reason = "explicit local delivery policy"' <<<"$git_state")"
    return 1
  fi
  origin_url="$(git -C "$WORKTREE" remote get-url origin 2>/dev/null || true)"
  github_remote=0
  case "$origin_url" in *github.com[:/]*) github_remote=1 ;; esac
  if ! command -v gh >/dev/null 2>&1; then
    if [[ "$policy" == "github" || "$github_remote" -eq 1 || -n "$TARGET_GITHUB_REPO" ]]; then
      die "gh required to resolve a GitHub delivery target; use explicit --delivery local only when local delivery is intended"
    fi
    update_state "$(jq '.delivery_mode = "local" | .delivery_fallback_reason = "GitHub CLI unavailable"' <<<"$git_state")"
    return 1
  fi
  if [[ -n "$TARGET_GITHUB_REPO" ]]; then
    metadata="$(gh repo view "$TARGET_GITHUB_REPO" --json nameWithOwner,url,visibility 2>/dev/null)" || metadata=""
  else
    metadata="$(cd "$WORKTREE" && gh repo view --json nameWithOwner,url,visibility 2>/dev/null)" || metadata=""
  fi
  if [[ -z "$metadata" ]]; then
    if [[ "$policy" == "github" || "$github_remote" -eq 1 || -n "$TARGET_GITHUB_REPO" ]]; then
      die "could not resolve the GitHub repository; check gh auth and the origin remote, or explicitly choose local delivery"
    fi
    update_state "$(jq '.delivery_mode = "local" | .delivery_fallback_reason = "GitHub repository or authentication unavailable"' <<<"$git_state")"
    return 1
  fi
  visibility="$(jq -r '.visibility' <<<"$metadata")"
  if [[ "$policy" == "auto" && "$visibility" != "PUBLIC" && "$private_policy" != "github" ]]; then
    fallback="auto policy keeps $(printf '%s' "$visibility" | tr '[:upper:]' '[:lower:]') repositories on local delivery"
    update_state "$(jq --arg repo "$(jq -r '.nameWithOwner' <<<"$metadata")" --arg visibility "$visibility" --arg reason "$fallback" \
      '.delivery_mode = "local" | .github_repo = $repo | .github_visibility = $visibility | .delivery_fallback_reason = $reason' <<<"$git_state")"
    return 1
  fi
  update_state "$(jq --arg repo "$(jq -r '.nameWithOwner' <<<"$metadata")" --arg visibility "$visibility" \
    '.delivery_mode = "github" | .github_repo = $repo | .github_visibility = $visibility | .delivery_fallback_reason = null' <<<"$git_state")"
  return 0
}

require_github_delivery() {
  local mode
  mode="$(jq -r '.delivery_mode // "unresolved"' <<<"$git_state")"
  if [[ "$mode" == "unresolved" ]]; then
    resolve_delivery || die "delivery resolved to local; use run-worktree.sh merge for this run"
  elif [[ "$mode" != "github" ]]; then
    die "delivery mode is local; use run-worktree.sh merge for this run"
  fi
  need_cmd gh
}

# True (exit 0) when the branch carries any diff against its base — false for a branch
# that is empty or holds only the empty "chore: start Bureau run" kickoff commit(s). Diffs
# against the merge-base rather than the base tip, so a base that has moved on since the
# branch forked doesn't get misread as "this branch has real changes."
branch_has_real_changes() {
  local base_ref merge_base
  git -C "$WORKTREE" rev-parse --verify "origin/$BASE" >/dev/null 2>&1 \
    || git -C "$WORKTREE" fetch origin "$BASE" >/dev/null 2>&1 || true
  if git -C "$WORKTREE" rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
    base_ref="origin/$BASE"
  else
    base_ref="$BASE"
  fi
  merge_base="$(git -C "$WORKTREE" merge-base "$base_ref" HEAD 2>/dev/null)" || merge_base="$base_ref"
  ! git -C "$WORKTREE" diff --quiet "$merge_base" HEAD -- 2>/dev/null
}

# Explicit --link-only/--closes-issue (persisted as git_state.pr_link_mode) always wins.
# Absent that, infer from the branch content itself so a run that never remembers the flag
# still gets the right answer, and a planning run that later gains real commits self-corrects
# on its next render instead of staying stuck on whatever was true at `open` time.
resolve_link_mode() {
  local mode
  mode="$(jq -r '.pr_link_mode // "auto"' <<<"$git_state")"
  case "$mode" in
    link-only|close) printf '%s' "$mode"; return ;;
  esac
  if branch_has_real_changes; then
    printf 'close'
  else
    printf 'link-only'
  fi
}

# Read the live GitHub-computed closing-issue count for a PR. This is the only reliable check:
# `gh pr view --json closingIssuesReferences` has been observed returning a stale count
# immediately after a body edit, and grepping the rendered body misses GitHub's own
# keyword parser matching a closing keyword inside unrelated prose (e.g. "must not close #93"
# still parses as "close #93" — negation is not part of the grammar it matches).
graphql_closing_count() {
  local repo="$1" pr="$2" owner name
  owner="${repo%%/*}"
  name="${repo#*/}"
  gh api graphql \
    -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){closingIssuesReferences(first:5){totalCount}}}}' \
    -f owner="$owner" -f name="$name" -F pr="$pr" \
    --jq '.data.repository.pullRequest.closingIssuesReferences.totalCount'
}

# Fail loudly, right when the body is written, if link-only mode did not actually keep the
# PR from closing its issue — rather than trusting the phrasing and finding out at merge time.
# Fails closed (not open) when the GraphQL check itself can't be answered: an unverifiable
# safeguard is not a passed one, same discipline as the CodeRabbit gate's own fail-closed
# design (docs/github-delivery.md § CodeRabbit) — silence and safety are indistinguishable
# otherwise, and this check exists specifically to catch a silent auto-close.
verify_link_mode() {
  local repo="$1" pr="$2" link_mode="$3" count
  [[ "$link_mode" == "link-only" ]] || return 0
  count="$(graphql_closing_count "$repo" "$pr" 2>&1)" \
    || die "could not verify PR #$pr's closing-issue references via GitHub's GraphQL API — cannot confirm --link-only/inferred link-only actually kept the issue open, so refusing rather than assuming it did: $count"
  [[ "$count" =~ ^[0-9]+$ ]] || die "unexpected response verifying PR #$pr's closing-issue references via GraphQL: $count"
  [[ "$count" == "0" ]] || die "PR #$pr still has $count closing issue reference(s) per GitHub's GraphQL API despite --link-only/inferred link-only — render_body's phrasing is tripping the closing-keyword parser; fix the wording, don't trust how the body reads"
}

render_body() {
  local issue_number="$1" evidence="$2" output="$3" link_mode
  link_mode="$(resolve_link_mode)"
  {
    if [[ "$link_mode" == "link-only" ]]; then
      printf 'Planning artifacts for issue #%s\n\n' "$issue_number"
    else
      printf 'Fixes #%s\n\n' "$issue_number"
    fi
    printf '%s\n\n' "Bureau run: \`$RUN_SLUG\`"
    sed -n '1,$p' "$evidence"
  } >"$output"
}

cmd_open() {
  require_worktree
  [[ -n "$PR_TITLE" ]] || die "--title required for open"
  if ! resolve_delivery; then
    echo "Delivery resolved to local. Use run-worktree.sh merge at close-out."
    return 0
  fi

  mkdir -p "$RUN_DIR/github"
  local issue_json issue_number issue_url evidence body pr_json pr_number pr_url kickoff origin_repo head_ref target_repo
  if [[ -n "$ISSUE" ]]; then
    issue_json="$(gh issue view "$ISSUE" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json number,url,title)" \
      || die "could not read linked issue: $ISSUE"
  else
    [[ -n "$ISSUE_TITLE" ]] || die "open requires --issue or --issue-title"
    [[ -f "$ISSUE_BODY_FILE" ]] || die "new issues require --issue-body-file with reproduction or acceptance criteria"
    issue_url="$(gh issue create --repo "$(jq -r '.github_repo' <<<"$git_state")" --title "$ISSUE_TITLE" --body-file "$ISSUE_BODY_FILE")" \
      || die "issue creation failed"
    issue_json="$(gh issue view "$issue_url" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json number,url,title)"
  fi
  issue_number="$(jq -r '.number' <<<"$issue_json")"
  issue_url="$(jq -r '.url' <<<"$issue_json")"
  update_state "$(jq --argjson issue "$issue_number" --arg issue_url "$issue_url" \
    '.issue_number = $issue | .issue_url = $issue_url | .status = "issue_linked"' <<<"$git_state")"
  if [[ -n "$LINK_MODE" ]]; then
    update_state "$(jq --arg mode "$LINK_MODE" '.pr_link_mode = $mode' <<<"$git_state")"
  fi

  evidence="$RUN_DIR/github/evidence.md"
  body="$RUN_DIR/github/pr-body.md"
  if [[ ! -f "$evidence" ]]; then
    {
      printf '## Problem and intended result\n\n%s\n\n' "${SUMMARY:-Pending — replace before ready for review.}"
      printf '## Important architectural decisions\n\n- Pending — replace before ready for review.\n\n'
      printf '## Testing performed\n\n- Pending — replace before ready for review.\n\n'
      printf '## Screenshots\n\n- Pending — attach/link screenshots or replace with a specific not-applicable reason.\n\n'
      printf '## Risks\n\n- Pending — replace before ready for review.\n\n'
      printf '## Rollback\n\n- Pending — replace before ready for review.\n\n'
      printf '## Bureau cold review\n\n- Pending — review has not passed yet.\n\n'
      printf '## Objection resolution\n\n- None recorded yet.\n'
    } >"$evidence"
  fi
  render_body "$issue_number" "$evidence" "$body"

  git -C "$WORKTREE" rev-parse --verify "origin/$BASE" >/dev/null 2>&1 \
    || git -C "$WORKTREE" fetch origin "$BASE"
  if [[ "$(git -C "$WORKTREE" rev-list --count "origin/$BASE..HEAD")" == "0" ]]; then
    kickoff="chore: start Bureau run $RUN_SLUG"
    git -C "$WORKTREE" commit --allow-empty -m "$kickoff"
  fi
  git -C "$WORKTREE" push -u origin "$BRANCH"
  update_state "$(jq '.status = "branch_pushed"' <<<"$git_state")"
  target_repo="$(jq -r '.github_repo' <<<"$git_state")"
  origin_repo="$(cd "$WORKTREE" && gh repo view --json nameWithOwner --jq '.nameWithOwner')"
  if [[ "$origin_repo" == "$target_repo" ]]; then
    head_ref="$BRANCH"
  else
    head_ref="$(printf '%s' "$origin_repo" | cut -d/ -f1):$BRANCH"
  fi
  # Bureau opens every PR as a draft, and CodeRabbit does not auto-review drafts, so a
  # target repo with no config gets its review silently skipped. WARN here rather than
  # writing the file: seeding it would dirty the worktree (cmd_merge requires it clean)
  # and land a path outside the run's declared scope. The merge gate fails closed on the
  # same condition, so this is an early notice, not the enforcement.
  if [[ -n "${WORKTREE:-}" && ! -f "$WORKTREE/.coderabbit.yaml" && ! -f "$WORKTREE/.coderabbit.yml" ]]; then
    echo "pr-delivery: WARNING $target_repo has no .coderabbit.yaml — CodeRabbit will SKIP this draft PR." >&2
    echo "pr-delivery:          Copy templates/coderabbit.yaml to the repo root and commit it," >&2
    echo "pr-delivery:          or coderabbit-gate.sh will block the merge." >&2
  fi
  pr_url="$(gh pr create --repo "$target_repo" --draft --base "$BASE" --head "$head_ref" --title "$PR_TITLE" --body-file "$body")" \
    || die "draft pull request creation failed"
  pr_json="$(gh pr view "$pr_url" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json number,url,isDraft)"
  pr_number="$(jq -r '.number' <<<"$pr_json")"
  pr_url="$(jq -r '.url' <<<"$pr_json")"

  # Record the PR before verifying its link mode: the PR already exists on GitHub at this
  # point, so if verify_link_mode dies below, state.json must still know about it — otherwise
  # a later `refresh` fails with "run open first" against a PR that is sitting there orphaned.
  update_state "$(jq \
    --argjson issue "$issue_number" --arg issue_url "$issue_url" \
    --argjson pr "$pr_number" --arg pr_url "$pr_url" --arg evidence "$evidence" \
    '.issue_number = $issue | .issue_url = $issue_url | .pr_number = $pr | .pr_url = $pr_url |
     .pr_is_draft = true | .pr_evidence_path = $evidence | .status = "pull_request_open"' <<<"$git_state")"
  verify_link_mode "$target_repo" "$pr_number" "$(resolve_link_mode)"

  echo "Issue: $issue_url"
  echo "Draft PR: $pr_url"
  echo "Evidence: $evidence"
}

cmd_refresh() {
  require_worktree
  require_github_delivery
  local pr issue evidence body
  pr="$(jq -r '.pr_number // empty' <<<"$git_state")"
  issue="$(jq -r '.issue_number // empty' <<<"$git_state")"
  evidence="$(jq -r '.pr_evidence_path // empty' <<<"$git_state")"
  [[ -n "$pr" && -n "$issue" ]] || die "no pull request/issue recorded; run open first"
  [[ -f "$evidence" ]] || die "evidence file missing: $evidence"
  body="$RUN_DIR/github/pr-body.md"
  render_body "$issue" "$evidence" "$body"
  gh pr edit "$pr" --repo "$(jq -r '.github_repo' <<<"$git_state")" --body-file "$body" >/dev/null
  verify_link_mode "$(jq -r '.github_repo' <<<"$git_state")" "$pr" "$(resolve_link_mode)"
  git -C "$WORKTREE" push origin "$BRANCH"
  echo "Updated PR #$pr and pushed $BRANCH"
}

cmd_review() {
  require_worktree
  require_github_delivery
  [[ -f "$REVIEW_SUMMARY" ]] || die "--review-summary FILE required"
  case "$VERDICT" in accepted|changes-requested) ;; *) die "--verdict must be accepted or changes-requested" ;; esac
  local pr actor author review_url head_sha repo_name review_mode
  pr="$(jq -r '.pr_number // empty' <<<"$git_state")"
  repo_name="$(jq -r '.github_repo // empty' <<<"$git_state")"
  [[ -n "$pr" && -n "$repo_name" ]] || die "no pull request recorded; run open first"
  [[ -z "$(git -C "$WORKTREE" status --porcelain)" ]] || die "worktree has uncommitted changes"
  git -C "$WORKTREE" push origin "$BRANCH"
  actor="$(gh api user --jq '.login')"
  author="$(gh pr view "$pr" --repo "$repo_name" --json author --jq '.author.login')"
  review_mode="comment"
  if [[ "$actor" != "$author" ]]; then
    if [[ "$VERDICT" == "accepted" ]]; then
      gh pr review "$pr" --repo "$repo_name" --approve --body-file "$REVIEW_SUMMARY"
      review_mode="approval"
    else
      gh pr review "$pr" --repo "$repo_name" --request-changes --body-file "$REVIEW_SUMMARY"
      review_mode="changes-requested"
    fi
  else
    gh pr comment "$pr" --repo "$repo_name" --body-file "$REVIEW_SUMMARY" >/dev/null
  fi

  review_url="$(jq -r '.pr_url' <<<"$git_state")"
  update_state "$(jq --arg status "$VERDICT" --arg url "$review_url" --arg mode "$review_mode" \
    '.cold_review_status = $status | .cold_review_url = $url | .cold_review_mode = $mode' <<<"$git_state")"

  if [[ -n "$INLINE_COMMENTS" ]]; then
    [[ -f "$INLINE_COMMENTS" ]] || die "inline comments file missing: $INLINE_COMMENTS"
    jq -e 'type == "array" and all(.[]; (.path|type)=="string" and (.line|type)=="number" and (.body|type)=="string")' "$INLINE_COMMENTS" >/dev/null \
      || die "inline comments must be a JSON array of {path,line,body[,side]}"
    head_sha="$(git -C "$WORKTREE" rev-parse HEAD)"
    while IFS= read -r comment; do
      gh api "repos/$repo_name/pulls/$pr/comments" --method POST \
        -f body="$(jq -r '.body' <<<"$comment")" \
        -f commit_id="$head_sha" \
        -f path="$(jq -r '.path' <<<"$comment")" \
        -F line="$(jq -r '.line' <<<"$comment")" \
        -f side="$(jq -r '.side // "RIGHT"' <<<"$comment")" >/dev/null
    done < <(jq -c '.[]' "$INLINE_COMMENTS")
  fi

  echo "Recorded $VERDICT cold review on PR #$pr ($review_mode)"
}

# Print a markdown file with fenced blocks and closed inline `code` spans removed.
# A fence line (opener or closer) is indented at most 3 columns. A fence closes only on a
# line of the opener's character, at least as long, with nothing but whitespace after it;
# an unclosed fence is printed as-is. A backtick run closes only on a run of the same
# length; an unmatched run stays, so text after it is still linted.
# Every other line is stripped on its own, except that a span may wrap the one line break
# between two plain paragraph lines (issue #149). A line is plain only when, after an
# indent of 3 columns or less, its first character is an ASCII letter or digit, it is not
# an ordered list marker line (digits, then . or ), then a blank or end of line), and it
# holds no pipe; every other line (list or quote marker, heading, HTML, fence, footnote or
# link reference definition, emphasis, a leading backtick, ...) is not plain.
# Two plain lines do not join when the first, stripped of its own closed spans, has a <
# before its first backtick: the < may open a raw HTML tag, autolink or comment holding that
# backtick, which then opens no span. In a joined run, a span that wraps the line break, or
# any later span on the line it closes on, is kept only if its text is <>-balanced (no >
# before its <, none left open): raw HTML and autolinks, the only inline constructs that
# outrank a code span, sit in < >. When a span fails, the whole run is stripped line by line,
# exactly as main strips it.
# Once a line that is not plain appears, every line up to the next blank line stands alone
# (a fence closing does not end that run: the fence may sit inside an HTML block). Once a
# line starts with <, at any indent and after any list or quote markers, no line joins for
# the rest of the file: an HTML block such as <pre> runs across blank lines. A line made only of - _ * = : | and
# blanks may be a table delimiter row whose header is the last line of the run before it
# (GFM), so each line of that run is stripped alone. A line that stands alone when
# CommonMark would join it only over-lints; a join CommonMark would not make can hide a
# placeholder.
strip_code_spans() {
  awk '
    function run_len(s, i, ch,   n) { n = 0; while (substr(s, i + n, 1) == ch) n++; return n }
    # A run where strip_inline rejected a span is stripped line by line instead, as on main.
    function flush(   x) {
      if (!have) return
      rejected = 0; x = strip_inline(para)
      if (rejected) flush_lines(); else { print x; para = ""; have = 0 }
    }
    # Strip each buffered line alone (the run sits above a possible table delimiter row).
    function flush_lines(   n, i, part) {
      if (have) { n = split(para, part, "\n"); for (i = 1; i <= n; i++) print strip_inline(part[i]) }
      para = ""; have = 0
    }
    # s may hold line breaks (a run of plain lines); a closer is looked for across at most one.
    function strip_inline(s,   out, i, n, r, k, m, found, b, nl, ch, after) {
      out = ""; i = 1; n = length(s); after = 0
      while (i <= n) {
        if (substr(s, i, 1) != "`") { if (substr(s, i, 1) == "\n") after = 0; out = out substr(s, i, 1); i++; continue }
        # An odd run of backslashes before an opener escapes its first backtick, so it is
        # literal text, not a span opener (CommonMark). Closers are not escapable.
        b = 0; while (i - b - 1 >= 1 && substr(s, i - b - 1, 1) == "\\") b++
        if (b % 2 == 1) { out = out "`"; i++; continue }
        r = run_len(s, i, "`"); k = i + r; found = 0; nl = 0
        while (k <= n) {
          ch = substr(s, k, 1)
          if (ch == "\n") { if (++nl > 1) break; k++; continue }
          if (ch != "`") { k++; continue }
          m = run_len(s, k, "`")
          if (m == r) { found = 1; break }
          k += m
        }
        # Only raw HTML and autolinks outrank a code span, and both sit in < >: a span that
        # wraps a line break, or follows a wrapped span on its closing line (where backticks
        # pair unlike that line alone), must hold <>-balanced text, or flush() splits the run.
        if (found && (nl || after) && !balanced(substr(s, i + r, k - i - r))) { found = 0; rejected = 1 }
        if (found) { i = k + m; if (nl) after = 1 } else { out = out substr(s, i, r); i += r }
      }
      return out
    }
    # 1 when every > closes an earlier < and none is left open (depth never below zero).
    function balanced(s,   d, j, ch) {
      d = 0
      for (j = 1; j <= length(s); j++) {
        ch = substr(s, j, 1)
        if (ch == "<") d++
        else if (ch == ">" && --d < 0) return 0
      }
      return d == 0
    }
    {
      # Indent in columns (a tab advances to the next multiple of 4). A fence opener or
      # closer may be indented at most 3 columns; at 4 or more the line is indented code
      # or paragraph text, not a fence (CommonMark, issue #149).
      col = 0; p = 1
      while (p <= length($0)) {
        ch = substr($0, p, 1)
        if (ch == " ") col++
        else if (ch == "\t") col += 4 - col % 4
        else break
        p++
      }
      t = substr($0, p); c = substr(t, 1, 1)
      if (fence) {
        buf = buf $0 "\n"
        if (col <= 3 && c == fc) {
          l = run_len(t, 1, c)
          if (l >= fl && substr(t, l + 1) ~ /^[[:space:]]*$/) { fence = 0; buf = "" }
        }
        next
      }
      if (col <= 3 && (c == "`" || c == "~")) {
        l = run_len(t, 1, c)
        # A backtick fence info string cannot hold a backtick; such a line opens no fence.
        if (l >= 3 && !(c == "`" && index(substr(t, l + 1), "`") > 0)) { flush(); fence = 1; fc = c; fl = l; buf = $0 "\n"; next }
      }
      if (t ~ /^[[:space:]]*$/) { flush(); mixed = 0; print; next }
      # Plain paragraph line test (see the comment above the function). The trailing trim
      # keeps a CRLF line end from hiding a bare numbered marker or a delimiter row.
      u = t; sub(/[[:space:]]+$/, "", u)
      if (u ~ /^(([-+*]|[0-9]+[.)])[ \t]+|>[ \t]*)*</) html = 1
      rule = u ~ /^[-_*=:| \t]+$/
      # Whitelist: starts with an ASCII letter or digit, is not an ordered list marker line, no pipe.
      plain = col <= 3 && u ~ /^[A-Za-z0-9]/ && u !~ /^[0-9]+[.)]([ \t]|$)/ && index(u, "|") == 0
      if (plain && !mixed && !html) {
        # Inline precedence: when the previous line, stripped of its own closed spans, has a <
        # before its first backtick, that < may open a raw HTML tag, autolink or comment that
        # holds the backtick (GitHub renders it literally), so the previous line does not join.
        if (have) { x = strip_inline(last); lt = index(x, "<"); bt = index(x, "`"); if (lt && bt && lt < bt) flush() }
        para = have ? para "\n" $0 : $0; have = 1; last = $0; next
      }
      if (rule) flush_lines(); else flush()
      if (!plain) mixed = 1
      print strip_inline($0)
    }
    END { flush(); if (fence) printf "%s", buf }
  ' "$1"
}

cmd_ready() {
  require_worktree
  require_github_delivery
  local pr evidence
  pr="$(jq -r '.pr_number // empty' <<<"$git_state")"
  evidence="$(jq -r '.pr_evidence_path // empty' <<<"$git_state")"
  [[ "$(jq -r '.cold_review_status // empty' <<<"$git_state")" == "accepted" ]] \
    || die "cold review has not been accepted"
  [[ -f "$evidence" ]] || die "evidence file missing: $evidence"
  [[ -z "$(git -C "$WORKTREE" status --porcelain)" ]] || die "worktree has uncommitted changes"
  # Angle brackets are placeholders only outside code: `x<k>` in an inline span or a fenced
  # block is literal syntax (issue #146). TBD/TODO/Pending still scan the raw file.
  # The strip is captured, not piped: a failed strip must refuse, not lint empty text, and
  # under pipefail an early `grep -q` exit could SIGPIPE awk and turn a placeholder into a pass.
  local stripped
  stripped="$(strip_code_spans "$evidence")" \
    || die "code-span strip failed on $evidence; cannot lint it for placeholder text"
  if grep -Eq 'Pending —|(^|[^[:alnum:]_])(TBD|TODO)([^[:alnum:]_]|$)' "$evidence" \
    || grep -Eq '<[^>]+>' <<<"$stripped"; then
    die "evidence still contains placeholder text; complete $evidence before ready"
  fi
  cmd_refresh
  gh pr ready "$pr" --repo "$(jq -r '.github_repo' <<<"$git_state")" >/dev/null
  update_state "$(jq '.pr_is_draft = false | .status = "ready_for_review"' <<<"$git_state")"
  echo "PR #$pr is ready for review"
}

cmd_coauthor() {
  require_worktree
  [[ "$CONFIRMED_HUMAN" -eq 1 ]] || die "--confirmed-human required; agents and nominal participants are not co-authors"
  [[ -n "$COAUTHOR_NAME" && -n "$COAUTHOR_EMAIL" ]] || die "--name and --email required"
  [[ "$COAUTHOR_EMAIL" == *@*.* ]] || die "co-author email does not look valid"
  local sha trailer
  sha="$(git -C "$WORKTREE" rev-parse "$COAUTHOR_COMMIT^{commit}" 2>/dev/null)" \
    || die "co-author commit not found: $COAUTHOR_COMMIT"
  git -C "$WORKTREE" merge-base --is-ancestor "$BASE" "$sha" \
    || die "co-author commit is not on the Bureau branch ancestry"
  git -C "$WORKTREE" merge-base --is-ancestor "$sha" HEAD \
    || die "co-author commit is not reachable from the Bureau branch"
  if git -C "$WORKTREE" merge-base --is-ancestor "$sha" "$BASE"; then
    die "co-author commit predates this Bureau branch"
  fi
  trailer="Co-authored-by: $COAUTHOR_NAME <$COAUTHOR_EMAIL>"
  git -C "$WORKTREE" show -s --format=%B "$sha" | grep -Fqx "$trailer" \
    || die "commit $sha does not contain the exact trailer: $trailer"
  update_state "$(jq --arg name "$COAUTHOR_NAME" --arg email "$COAUTHOR_EMAIL" --arg commit "$sha" \
    '.coauthors = ((.coauthors // []) + [{name:$name,email:$email,commit:$commit}] | unique_by([.email,.commit]))' <<<"$git_state")"
  echo "Recorded genuine co-author $COAUTHOR_NAME on $sha"
}

cmd_merge() {
  require_worktree
  require_github_delivery
  case "$MERGE_METHOD" in merge|squash|rebase) ;; *) die "--merge-method must be merge, squash, or rebase" ;; esac
  local pr pr_json flag now
  pr="$(jq -r '.pr_number // empty' <<<"$git_state")"
  [[ -n "$pr" ]] || die "no pull request recorded; run open first"
  [[ "$(jq -r '.cold_review_status // empty' <<<"$git_state")" == "accepted" ]] \
    || die "cold review has not been accepted"
  [[ -z "$(git -C "$WORKTREE" status --porcelain)" ]] || die "worktree has uncommitted changes"
  pr_json="$(gh pr view "$pr" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json isDraft,state,reviewDecision,mergeStateStatus,url)"
  [[ "$(jq -r '.state' <<<"$pr_json")" == "OPEN" ]] || die "PR #$pr is not open"
  [[ "$(jq -r '.isDraft' <<<"$pr_json")" == "false" ]] || die "PR #$pr is still a draft"
  [[ "$(jq -r '.reviewDecision // ""' <<<"$pr_json")" != "CHANGES_REQUESTED" ]] || die "PR #$pr has unresolved requested changes"
  # CodeRabbit posts as an issue comment, never a formal review, so the
  # reviewDecision check above is structurally blind to it. Gate separately.
  # Opt a repo out with state.json#git.coderabbit_gate = "skip" (record why).
  if [[ "$(jq -r '.coderabbit_gate // ""' <<<"$git_state")" != "skip" ]]; then
    local cr_out cr_rc
    cr_out="$(bash "$(dirname "${BASH_SOURCE[0]}")/coderabbit-gate.sh" "$RUN_DIR" 2>&1)"; cr_rc=$?
    if [[ $cr_rc -ne 0 ]]; then
      printf '%s\n' "$cr_out" >&2
      die "CodeRabbit gate failed for PR #$pr — resolve the defects above, or set state.json#git.coderabbit_gate=\"skip\" with a logged reason"
    fi
    printf '%s\n' "$cr_out"
  fi
  flag="--$MERGE_METHOD"
  gh pr merge "$pr" --repo "$(jq -r '.github_repo' <<<"$git_state")" "$flag"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  update_state "$(jq --arg now "$now" '.status = "merged" | .merged_at = $now | .pr_is_draft = false' <<<"$git_state")"
  echo "Merged PR #$pr through GitHub"
}

cmd_status() {
  local mode pr
  mode="$(jq -r '.delivery_mode // "unresolved"' <<<"$git_state")"
  if [[ "$mode" == "unresolved" ]]; then
    require_worktree
    resolve_delivery || true
    mode="$(jq -r '.delivery_mode' <<<"$git_state")"
  fi
  echo "Delivery mode: $mode"
  jq '{delivery_policy,private_delivery,delivery_mode,delivery_fallback_reason,github_repo,github_visibility,issue_number,issue_url,pr_number,pr_url,pr_is_draft,cold_review_status,cold_review_mode,coauthors,status}' <<<"$git_state"
  pr="$(jq -r '.pr_number // empty' <<<"$git_state")"
  if [[ "$mode" == "github" && -n "$pr" ]]; then
    gh pr view "$pr" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json number,url,state,isDraft,reviewDecision,mergeStateStatus
    if [[ -d "$WORKTREE" ]]; then
      local link_mode closing_count repo_name
      link_mode="$(resolve_link_mode)"
      repo_name="$(jq -r '.github_repo' <<<"$git_state")"
      closing_count="$(graphql_closing_count "$repo_name" "$pr" 2>/dev/null)" || closing_count="unknown"
      echo "PR link mode: $link_mode (closingIssuesReferences via GraphQL: $closing_count — the authoritative check, not the rendered body)"
    fi
  fi
}

case "$CMD" in
  open) cmd_open ;;
  refresh) cmd_refresh ;;
  review) cmd_review ;;
  coauthor) cmd_coauthor ;;
  ready) cmd_ready ;;
  merge) cmd_merge ;;
  status) cmd_status ;;
  *) die "unknown subcommand: $CMD" ;;
esac
