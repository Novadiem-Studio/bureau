#!/usr/bin/env bash
# Git worktree lifecycle for Society execute runs.
#
# Usage:
#   ./scripts/run-worktree.sh create --run-dir RUN_DIR --repo REPO_PATH [options]
#   ./scripts/run-worktree.sh merge  --run-dir RUN_DIR [--message MSG]
#   ./scripts/run-worktree.sh sync   --run-dir RUN_DIR   # rebase society branch onto base
#   ./scripts/run-worktree.sh remove --run-dir RUN_DIR [--force]
#   ./scripts/run-worktree.sh status --run-dir RUN_DIR
#
# Options (create):
#   --base BRANCH          default: devel
#   --slug SLUG            default: basename of RUN_DIR
#   --merge-policy POLICY  end_of_job | per_prompt | checkpoint (default: end_of_job)
#   --worktree-dir PATH    default: REPO/.society-worktrees/SLUG

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

  git -C "$REPO" rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 \
    || die "base branch not found: $BASE_BRANCH (in $REPO)"

  local branch="society/${SLUG}"
  if [[ -z "$WORKTREE_DIR" ]]; then
    WORKTREE_DIR="$REPO/.society-worktrees/$SLUG"
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
    --arg slug "$SLUG" \
    --arg created "$now" \
    '{
      enabled: true,
      repo: $repo,
      base_branch: $base,
      branch: $branch,
      worktree_path: $worktree,
      merge_policy: $policy,
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
  local repo wt base branch policy
  repo="$(jq -r '.repo' <<<"$git")"
  wt="$(jq -r '.worktree_path' <<<"$git")"
  base="$(jq -r '.base_branch' <<<"$git")"
  branch="$(jq -r '.branch' <<<"$git")"
  policy="$(jq -r '.merge_policy' <<<"$git")"
  [[ -d "$wt" ]] || die "worktree missing: $wt"

  # Ensure society branch commits are flushed
  if ! git -C "$wt" diff --quiet || ! git -C "$wt" diff --cached --quiet; then
    die "uncommitted changes in worktree — commit or stash before merge"
  fi

  git -C "$repo" fetch origin "$base" 2>/dev/null || true

  local msg
  msg="${MERGE_MSG:-Society run merge: $branch → $base ($policy)}"

  # Merge society branch into base at the main repo checkout
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
  local repo wt branch status
  repo="$(jq -r '.repo' <<<"$git")"
  wt="$(jq -r '.worktree_path' <<<"$git")"
  branch="$(jq -r '.branch' <<<"$git")"
  status="$(jq -r '.status' <<<"$git")"

  if [[ -d "$wt" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      git -C "$repo" worktree remove --force "$wt"
    else
      git -C "$repo" worktree remove "$wt"
    fi
  fi

  if [[ "$status" == "merged" ]]; then
    git -C "$repo" branch -d "$branch" 2>/dev/null || true
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
