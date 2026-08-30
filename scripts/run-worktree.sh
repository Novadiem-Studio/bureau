#!/usr/bin/env bash
# Git worktree lifecycle for Bureau execute runs.
#
# Usage:
#   ./scripts/run-worktree.sh create --run-dir RUN_DIR --repo REPO_PATH [options]
#   ./scripts/run-worktree.sh merge  --run-dir RUN_DIR [--message MSG]
#   ./scripts/run-worktree.sh sync   --run-dir RUN_DIR   # rebase bureau branch onto base
#   ./scripts/run-worktree.sh remove --run-dir RUN_DIR [--force]
#   ./scripts/run-worktree.sh status --run-dir RUN_DIR
#
# Options (create):
#   --base BRANCH          default: devel
#   --slug SLUG            default: basename of RUN_DIR
#   --merge-policy POLICY  end_of_job | per_prompt | checkpoint (default: end_of_job)
#   --delivery POLICY      auto | github | local (default: auto)
#   --private-delivery P   github | local (default: local; used when --delivery auto)
#   --worktree-dir PATH    default: $HOME/.bureau/worktrees/REPO_BASENAME/SLUG (override: BUREAU_WORKTREE_ROOT)

set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "run-worktree: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 required"
}

RUN_DIR=""
REPO=""
BASE_BRANCH="devel"
SLUG=""
MERGE_POLICY="end_of_job"
DELIVERY_POLICY="auto"
PRIVATE_DELIVERY="local"
WORKTREE_DIR=""
MERGE_MSG=""
FORCE=0
CMD="${1:-}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    create|merge|sync|remove|status) CMD="$1"; shift ;;
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    --merge-policy) MERGE_POLICY="$2"; shift 2 ;;
    --delivery) DELIVERY_POLICY="$2"; shift 2 ;;
    --private-delivery) PRIVATE_DELIVERY="$2"; shift 2 ;;
    --worktree-dir) WORKTREE_DIR="$2"; shift 2 ;;
    --message) MERGE_MSG="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$CMD" ]] || usage 1

need_cmd git
need_cmd jq

state_file() {
  [[ -n "$RUN_DIR" ]] || die "--run-dir required"
  [[ -f "$RUN_DIR/state.json" ]] || die "state.json not found in $RUN_DIR"
  printf '%s/state.json' "$RUN_DIR"
}

read_git_state() {
  jq -c '.git // {}' "$(state_file)"
}

write_git_state() {
  local git_json="$1"
  local sf
  sf="$(state_file)"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/state.XXXXXX")"
  jq --argjson git "$git_json" '.git = $git | .last_updated = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' "$sf" >"$tmp"
  mv "$tmp" "$sf"
}

cmd_create() {
  [[ -n "$REPO" ]] || die "--repo required for create"
  [[ -d "$REPO/.git" || -f "$REPO/.git" ]] || die "not a git repo: $REPO"
  REPO="$(cd "$REPO" && pwd)"

  local sf
  sf="$(state_file)"
  RUN_DIR="$(cd "$RUN_DIR" && pwd)"

  if [[ -z "$SLUG" ]]; then
    SLUG="$(basename "$RUN_DIR")"
  fi
  SLUG="$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"

  case "$MERGE_POLICY" in
    end_of_job|per_prompt|checkpoint) ;;
    *) die "invalid --merge-policy: $MERGE_POLICY" ;;
  esac
  case "$DELIVERY_POLICY" in
    auto|github|local) ;;
    *) die "invalid --delivery: $DELIVERY_POLICY" ;;
  esac
  case "$PRIVATE_DELIVERY" in
    github|local) ;;
    *) die "invalid --private-delivery: $PRIVATE_DELIVERY" ;;
  esac
  if [[ "$DELIVERY_POLICY" != "local" && "$MERGE_POLICY" != "end_of_job" ]]; then
    die "GitHub/auto delivery supports only --merge-policy end_of_job; use --delivery local for incremental local merges"
  fi

  git -C "$REPO" rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 \
    || die "base branch not found: $BASE_BRANCH (in $REPO)"

  local branch="bureau/${SLUG}"
  if [[ -z "$WORKTREE_DIR" ]]; then
    WORKTREE_DIR="${BUREAU_WORKTREE_ROOT:-$HOME/.bureau/worktrees}/$(basename "$REPO")/$SLUG"
  fi
  mkdir -p "$(dirname "$WORKTREE_DIR")"

  if [[ -d "$WORKTREE_DIR" ]]; then
    die "worktree path already exists: $WORKTREE_DIR"
  fi

  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch"; then
    die "branch already exists: $branch — pick a different --slug"
  fi

  git -C "$REPO" worktree add -b "$branch" "$WORKTREE_DIR" "$BASE_BRANCH"

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local git_json
  git_json="$(jq -n \
    --arg repo "$REPO" \
    --arg base "$BASE_BRANCH" \
    --arg branch "$branch" \
    --arg worktree "$WORKTREE_DIR" \
    --arg policy "$MERGE_POLICY" \
    --arg delivery "$DELIVERY_POLICY" \
    --arg private_delivery "$PRIVATE_DELIVERY" \
    --arg slug "$SLUG" \
    --arg created "$now" \
    '{
      enabled: true,
      repo: $repo,
      base_branch: $base,
      branch: $branch,
      worktree_path: $worktree,
      merge_policy: $policy,
      delivery_policy: $delivery,
      private_delivery: $private_delivery,
      delivery_mode: "unresolved",
      delivery_fallback_reason: null,
      github_repo: null,
      github_visibility: null,
      issue_number: null,
      issue_url: null,
      pr_number: null,
      pr_url: null,
      pr_is_draft: null,
      pr_evidence_path: null,
      cold_review_status: null,
      cold_review_url: null,
      coauthors: [],
      run_slug: $slug,
      prompts_merged: [],
      status: "active",
      created_at: $created,
      merged_at: null,
      last_sync_at: null
    }')"

  write_git_state "$git_json"

  echo "Created worktree: $WORKTREE_DIR"
  echo "Branch: $branch (from $BASE_BRANCH)"
  echo "Merge policy: $MERGE_POLICY"
  echo "Recorded in: $sf"
}

cmd_status() {
  local git
  git="$(read_git_state)"
  [[ "$(jq -r '.enabled // false' <<<"$git")" == "true" ]] || die "no worktree recorded in state.json"
  jq '.' <<<"$git"
  local wt
  wt="$(jq -r '.worktree_path' <<<"$git")"
  if [[ -d "$wt" ]]; then
    echo "---"
    git -C "$wt" status -sb
  else
    echo "--- worktree path missing on disk: $wt" >&2
  fi
}

cmd_sync() {
  local git
  git="$(read_git_state)"
  local repo wt base branch
  repo="$(jq -r '.repo' <<<"$git")"
  wt="$(jq -r '.worktree_path' <<<"$git")"
  base="$(jq -r '.base_branch' <<<"$git")"
  branch="$(jq -r '.branch' <<<"$git")"
  [[ -d "$wt" ]] || die "worktree missing: $wt"

  git -C "$repo" fetch origin "$base" 2>/dev/null || true
  git -C "$wt" rebase "$base"

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_git_state "$(jq --arg now "$now" '.last_sync_at = $now' <<<"$git")"
  echo "Rebased $branch onto $base in $wt"
}

cmd_merge() {
  local git
  git="$(read_git_state)"
  local repo wt base branch policy delivery_policy delivery_mode
  repo="$(jq -r '.repo' <<<"$git")"
  wt="$(jq -r '.worktree_path' <<<"$git")"
  base="$(jq -r '.base_branch' <<<"$git")"
  branch="$(jq -r '.branch' <<<"$git")"
  policy="$(jq -r '.merge_policy' <<<"$git")"
  delivery_policy="$(jq -r '.delivery_policy // "local"' <<<"$git")"
  delivery_mode="$(jq -r '.delivery_mode // "unresolved"' <<<"$git")"
  [[ -d "$wt" ]] || die "worktree missing: $wt"

  if [[ "$delivery_policy" != "local" && "$delivery_mode" != "local" ]]; then
    die "local merge disabled for delivery policy '$delivery_policy' (resolved mode: '$delivery_mode') — use pr-delivery.sh open/ready/merge; auto mode must be resolved before a local fallback merge"
  fi

  # Ensure bureau branch commits are flushed
  if ! git -C "$wt" diff --quiet || ! git -C "$wt" diff --cached --quiet; then
    die "uncommitted changes in worktree — commit or stash before merge"
  fi

  git -C "$repo" fetch origin "$base" 2>/dev/null || true

  local msg
  msg="${MERGE_MSG:-Bureau run merge: $branch → $base ($policy)}"

  # Merge bureau branch into base at the main repo checkout
  local prev_branch
  prev_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  git -C "$repo" checkout "$base"
  if ! git -C "$repo" merge --no-ff "$branch" -m "$msg"; then
    git -C "$repo" merge --abort 2>/dev/null || true
    [[ -n "$prev_branch" && "$prev_branch" != "HEAD" ]] && git -C "$repo" checkout "$prev_branch" 2>/dev/null || true
    die "merge failed — resolve conflicts manually in $repo on $base, then update state.json"
  fi
  [[ -n "$prev_branch" && "$prev_branch" != "HEAD" && "$prev_branch" != "$base" ]] \
    && git -C "$repo" checkout "$prev_branch" 2>/dev/null || true

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_git_state "$(jq --arg now "$now" '.status = "merged" | .merged_at = $now' <<<"$git")"
  echo "Merged $branch → $base in $repo"
}

cmd_remove() {
  local git
  git="$(read_git_state)"
  local repo wt branch status delivery_mode
  repo="$(jq -r '.repo' <<<"$git")"
  wt="$(jq -r '.worktree_path' <<<"$git")"
  branch="$(jq -r '.branch' <<<"$git")"
  status="$(jq -r '.status' <<<"$git")"
  delivery_mode="$(jq -r '.delivery_mode // "local"' <<<"$git")"

  if [[ -d "$wt" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      git -C "$repo" worktree remove --force "$wt"
    else
      git -C "$repo" worktree remove "$wt"
    fi
  fi

  if [[ "$status" == "merged" ]]; then
    if [[ "$delivery_mode" == "github" ]]; then
      # A squash/rebase merge does not make the feature tip an ancestor of the local base.
      # GitHub already accepted the exact PR, so remove this exact local run branch explicitly.
      git -C "$repo" branch -D "$branch" 2>/dev/null || true
    else
      git -C "$repo" branch -d "$branch" 2>/dev/null || true
    fi
  fi

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_git_state "$(jq --arg now "$now" '.status = "removed" | .worktree_removed_at = $now' <<<"$git")"
  echo "Removed worktree: $wt"
}

case "$CMD" in
  create) cmd_create ;;
  merge) cmd_merge ;;
  sync) cmd_sync ;;
  remove) cmd_remove ;;
  status) cmd_status ;;
  -h|--help) usage 0 ;;
  *) usage 1 ;;
esac
