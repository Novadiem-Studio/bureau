#!/usr/bin/env bash
# cursor-cloud-target.sh — decide how a Cursor cloud specialist reaches the target repo.
#
# Usage:
#   cursor-cloud-target.sh [--workspace PATH] <RUN_DIR>
#
# Prints one JSON object on stdout:
#   mode = task-same-workspace | cloud-api-target
#
# task-same-workspace: the Cursor session already is the target (or a Bureau
# self-run). Task environment:cloud clones this workspace; do not call the
# Cloud Agents API.
#
# cloud-api-target: the session is the Bureau install (or anything else) and
# the target is a different git repo. Task environment:cloud would clone the
# wrong tree. The Cloud Agents API repos array must clone the target only —
# never vendor the Bureau onto that VM.
#
# Exit 0 on success. Exit 2 on a contract error (no target, no GitHub URL).

set -u
umask 077

WORKSPACE="${CURSOR_WORKSPACE:-}"
if [ "${1:-}" = "--workspace" ]; then
  [ "$#" -ge 3 ] || {
    echo "cursor-cloud-target: usage: [--workspace PATH] <RUN_DIR>" >&2
    exit 2
  }
  WORKSPACE="$2"
  shift 2
fi

if [ "$#" -ne 1 ]; then
  echo "cursor-cloud-target: usage: [--workspace PATH] <RUN_DIR>" >&2
  exit 2
fi

RUN_DIR="$1"

fail() {
  echo "cursor-cloud-target: $*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v git >/dev/null 2>&1 || fail "git is required"

[ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || fail "cannot resolve RUN_DIR"
STATE="$RUN_DIR/state.json"
[ -s "$STATE" ] || fail "state.json is absent or empty"

TARGET="$(jq -r '.target_repo // empty' "$STATE" 2>/dev/null)"
[ -n "$TARGET" ] || fail "state.json has no target_repo"
[ "$TARGET" != "(no-target)" ] || fail "cloud specialists need a real git target, not (no-target)"
[ -d "$TARGET" ] || fail "target_repo is not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd -P)" || fail "cannot resolve target_repo"

if [ -z "$WORKSPACE" ]; then
  WORKSPACE="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -n "$WORKSPACE" ] && [ -d "$WORKSPACE" ]; then
  WORKSPACE="$(cd "$WORKSPACE" && pwd -P)" || WORKSPACE=""
fi

github_https_from_remote() {
  local raw="$1"
  raw="${raw%.git}"
  case "$raw" in
    git@github.com:*)
      printf 'https://github.com/%s\n' "${raw#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      printf 'https://github.com/%s\n' "${raw#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      printf '%s\n' "$raw"
      ;;
    http://github.com/*)
      printf 'https://github.com/%s\n' "${raw#http://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
}

GITHUB_REPO="$(jq -r '.git.github_repo // empty' "$STATE" 2>/dev/null)"
GITHUB_URL=""
if [ -n "$GITHUB_REPO" ] && [[ "$GITHUB_REPO" == */* ]] && [[ "$GITHUB_REPO" != *://* ]]; then
  GITHUB_URL="https://github.com/${GITHUB_REPO}"
else
  ORIGIN="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  [ -n "$ORIGIN" ] || fail "target has no git.github_repo and no origin remote"
  GITHUB_URL="$(github_https_from_remote "$ORIGIN")" \
    || fail "origin is not a GitHub remote: $ORIGIN"
fi

PR_URL="$(jq -r '.git.pr_url // empty' "$STATE" 2>/dev/null)"
BRANCH="$(jq -r '.git.branch // empty' "$STATE" 2>/dev/null)"
BASE="$(jq -r '.git.base_branch // empty' "$STATE" 2>/dev/null)"
[ -n "$BASE" ] || BASE="devel"
STARTING_REF="$BASE"
[ -n "$BRANCH" ] && STARTING_REF="$BRANCH"

WORK_ON_CURRENT=false
if [ -n "$PR_URL" ]; then
  WORK_ON_CURRENT=true
fi

MODE="cloud-api-target"
REASON="Task environment:cloud would clone the current workspace, not the target; use Cloud Agents API repos[] with the target only"
if [ -n "$WORKSPACE" ] && [ "$WORKSPACE" = "$TARGET" ]; then
  MODE="task-same-workspace"
  REASON="current workspace is the target repo; Task environment:cloud clones it"
fi

jq -n \
  --arg mode "$MODE" \
  --arg reason "$REASON" \
  --arg workspace "${WORKSPACE:-}" \
  --arg target "$TARGET" \
  --arg githubUrl "$GITHUB_URL" \
  --arg startingRef "$STARTING_REF" \
  --arg prUrl "$PR_URL" \
  --argjson workOnCurrentBranch "$WORK_ON_CURRENT" \
  '{
    mode: $mode,
    reason: $reason,
    workspace: $workspace,
    target: $target,
    doNotVendorBureau: true,
    autoCreatePR: false,
    workOnCurrentBranch: $workOnCurrentBranch,
    repos: (
      if $mode == "cloud-api-target" then
        [
          {
            url: $githubUrl,
            startingRef: $startingRef
          }
          + (if $prUrl != "" then {prUrl: $prUrl} else {} end)
        ]
      else
        []
      end
    )
  }'
