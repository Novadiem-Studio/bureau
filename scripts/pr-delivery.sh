#!/usr/bin/env bash
# GitHub-native delivery for Bureau worktree runs.
#
# Usage:
#   pr-delivery.sh open    --run-dir RUN_DIR (--issue NUMBER|URL | --issue-title TITLE --issue-body-file FILE) --title TITLE [--summary TEXT] [--github-repo OWNER/REPO]
#   pr-delivery.sh refresh --run-dir RUN_DIR
#   pr-delivery.sh review  --run-dir RUN_DIR --review-summary FILE --verdict accepted|changes-requested [--inline-comments FILE]
#   pr-delivery.sh coauthor --run-dir RUN_DIR --name NAME --email EMAIL [--commit SHA] --confirmed-human
#   pr-delivery.sh ready   --run-dir RUN_DIR
#   pr-delivery.sh merge   --run-dir RUN_DIR [--merge-method merge|squash|rebase]
#   pr-delivery.sh status  --run-dir RUN_DIR
#
# Public repositories resolve auto delivery to GitHub. Private/internal repositories use
# state.json#git.private_delivery (local by default). Explicit github delivery fails closed.

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
    --name) COAUTHOR_NAME="$2"; shift 2 ;;
    --email) COAUTHOR_EMAIL="$2"; shift 2 ;;
    --commit) COAUTHOR_COMMIT="$2"; shift 2 ;;
    --confirmed-human) CONFIRMED_HUMAN=1; shift ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
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
  private_policy="$(jq -r '.private_delivery // "local"' <<<"$git_state")"
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

render_body() {
  local issue_number="$1" evidence="$2" output="$3"
  {
    printf 'Fixes #%s\n\n' "$issue_number"
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
  pr_url="$(gh pr create --repo "$target_repo" --draft --base "$BASE" --head "$head_ref" --title "$PR_TITLE" --body-file "$body")" \
    || die "draft pull request creation failed"
  pr_json="$(gh pr view "$pr_url" --repo "$(jq -r '.github_repo' <<<"$git_state")" --json number,url,isDraft)"
  pr_number="$(jq -r '.number' <<<"$pr_json")"
  pr_url="$(jq -r '.url' <<<"$pr_json")"

  update_state "$(jq \
    --argjson issue "$issue_number" --arg issue_url "$issue_url" \
    --argjson pr "$pr_number" --arg pr_url "$pr_url" --arg evidence "$evidence" \
    '.issue_number = $issue | .issue_url = $issue_url | .pr_number = $pr | .pr_url = $pr_url |
     .pr_is_draft = true | .pr_evidence_path = $evidence | .status = "pull_request_open"' <<<"$git_state")"
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
  if grep -Eq 'Pending —|<[^>]+>|(^|[^[:alnum:]_])(TBD|TODO)([^[:alnum:]_]|$)' "$evidence"; then
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
