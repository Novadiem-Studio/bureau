#!/usr/bin/env bash
# coderabbit-gate.sh — merge gate: has CodeRabbit reviewed THIS head, and were its
# findings dispositioned?
#
# Usage:
#   coderabbit-gate.sh <RUN_DIR>
#   coderabbit-gate.sh --repo OWNER/REPO --pr N [--log LOG_MD]   (direct mode)
#
# Offline test seam (no network; all three must be given together):
#   --comments-file FILE   bot comment bodies, as the API would return them
#   --head SHA             the PR head to compare the reviewed range against
#   --inline-count N       number of inline review comments from the bot
#
# Exit codes (mirrors preflight-artifacts.sh / spawn-gate.sh):
#   0  + "coderabbit: clean"   reviewed at the current head; findings zero or dispositioned
#   1  + DEFECT line(s)        not reviewed, stale, or findings left undispositioned
#   2                          cannot run (bad args, no PR recorded, gh/jq missing)
#
# WHY THIS EXISTS. CodeRabbit posts as an ISSUE COMMENT from coderabbitai[bot], never
# as a formal review: `gh pr view --json reviews` returns [] and reviewDecision is "".
# pr-delivery.sh's `reviewDecision != CHANGES_REQUESTED` check therefore can NEVER see
# a CodeRabbit finding. This gate reads the bot's comments directly instead.
#
# THE TRAP THIS GATE EXISTS TO AVOID. CodeRabbit comments even when it has NOT reviewed:
#   - draft PRs        -> "skip review by coderabbit.ai"  (Bureau opens every PR --draft)
#   - rate limit/credits -> "rate limited by coderabbit.ai"
# A naive "did the bot comment?" check passes in both cases. Presence of a comment is not
# evidence of a review; only the reviewed-commit range is.
#
# Bash 3.2 + gh + jq; macOS portable. No set -e (we inspect exit codes).

PATH=/usr/bin:$PATH  # EC 10 — ugrep guard

RUN_DIR=""; REPO=""; PR=""; LOG_MD=""
COMMENTS_FILE=""; HEAD_OVERRIDE=""; INLINE_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="$2";            shift 2 ;;
    --pr)            PR="$2";              shift 2 ;;
    --log)           LOG_MD="$2";          shift 2 ;;
    --comments-file) COMMENTS_FILE="$2";   shift 2 ;;
    --head)          HEAD_OVERRIDE="$2";   shift 2 ;;
    --inline-count)  INLINE_OVERRIDE="$2"; shift 2 ;;
    -*)              echo "coderabbit-gate: unknown flag $1" >&2; exit 2 ;;
    *)               RUN_DIR="$1"; shift ;;
  esac
done

OFFLINE=0
if [ -n "$COMMENTS_FILE" ] || [ -n "$HEAD_OVERRIDE" ] || [ -n "$INLINE_OVERRIDE" ]; then
  if [ -z "$COMMENTS_FILE" ] || [ -z "$HEAD_OVERRIDE" ] || [ -z "$INLINE_OVERRIDE" ]; then
    echo "coderabbit-gate: --comments-file, --head and --inline-count must be given together" >&2
    exit 2
  fi
  [ -r "$COMMENTS_FILE" ] || { echo "coderabbit-gate: unreadable --comments-file" >&2; exit 2; }
  OFFLINE=1
  [ -n "$REPO" ] || REPO="offline/offline"
  [ -n "$PR" ] || PR="0"
fi

[ "$OFFLINE" -eq 1 ] || command -v gh >/dev/null 2>&1 || { echo "coderabbit-gate: gh required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "coderabbit-gate: jq required" >&2; exit 2; }

if [ -n "$RUN_DIR" ]; then
  [ -d "$RUN_DIR" ] || { echo "coderabbit-gate: RUN_DIR not a directory: $RUN_DIR" >&2; exit 2; }
  state="$RUN_DIR/state.json"
  [ -r "$state" ] || { echo "coderabbit-gate: no readable state.json in $RUN_DIR" >&2; exit 2; }
  REPO=$(jq -r '.git.github_repo // empty' "$state" 2>/dev/null)
  PR=$(jq -r '.git.pr_number // empty' "$state" 2>/dev/null)
  [ -z "$LOG_MD" ] && LOG_MD="$RUN_DIR/log.md"
fi

[ -n "$REPO" ] || { echo "coderabbit-gate: no github_repo (state.json#git.github_repo or --repo)" >&2; exit 2; }
[ -n "$PR" ]   || { echo "coderabbit-gate: no pr_number (state.json#git.pr_number or --pr)" >&2; exit 2; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
DEFECTS="$WORK/defects.txt"; : > "$DEFECTS"
defect() { printf 'DEFECT — coderabbit — %s\n' "$1" >> "$DEFECTS"; }

# ── The PR's current head ─────────────────────────────────────────────────────
if [ "$OFFLINE" -eq 1 ]; then
  head_sha="$HEAD_OVERRIDE"
  is_draft=false
else
  pr_json="$WORK/pr.json"
  if ! gh pr view "$PR" --repo "$REPO" --json headRefOid,isDraft,state,url > "$pr_json" 2>/dev/null; then
    echo "coderabbit-gate: cannot read PR #$PR in $REPO" >&2; exit 2
  fi
  head_sha=$(jq -r '.headRefOid // ""' "$pr_json")
  is_draft=$(jq -r '.isDraft // false' "$pr_json")
fi
[ -n "$head_sha" ] || { echo "coderabbit-gate: PR #$PR has no head sha" >&2; exit 2; }

# ── The bot's comments ────────────────────────────────────────────────────────
bodies="$WORK/bodies.txt"
if [ "$OFFLINE" -eq 1 ]; then
  cat "$COMMENTS_FILE" > "$bodies"
else
  gh api "repos/$REPO/issues/$PR/comments" --paginate \
    --jq '.[] | select(.user.login=="coderabbitai[bot]") | .body' > "$bodies" 2>/dev/null
fi

if [ ! -s "$bodies" ]; then
  if [ "$is_draft" = "true" ]; then
    defect "no CodeRabbit comment on PR #$PR (still a draft). CodeRabbit does not auto-review drafts; add .coderabbit.yaml with reviews.auto_review.drafts: true (see templates/coderabbit.yaml), or mark the PR ready before gating."
  else
    defect "no CodeRabbit comment on PR #$PR at all — the app is not installed on $REPO, or the review has not started yet. A merge here would ship unreviewed by CodeRabbit."
  fi
fi

# Non-review states. The bot DOES comment in both; neither is a review.
if grep -q 'skip review by coderabbit.ai' "$bodies" 2>/dev/null; then
  defect "CodeRabbit SKIPPED the review (draft PR). Bureau opens every PR with --draft (pr-delivery.sh open), so this is the default outcome without config: set reviews.auto_review.drafts: true in the target repo's .coderabbit.yaml (templates/coderabbit.yaml)."
fi
if grep -q 'rate limited by coderabbit.ai' "$bodies" 2>/dev/null; then
  defect "CodeRabbit was RATE LIMITED and did not review (plan limit or exhausted credits). Re-trigger with an '@coderabbitai review' PR comment once capacity returns; do not merge on the assumption it passed."
fi

# ── Did it review THIS head? ──────────────────────────────────────────────────
# A real review names its commit range: "between <base_sha> and <head_sha>".
# Last occurrence wins — the bot edits its summary in place on each new push.
reviewed_sha=$(grep -oE 'between [0-9a-f]{40} and [0-9a-f]{40}' "$bodies" 2>/dev/null \
  | tail -1 | awk '{print $4}')

if [ -n "$reviewed_sha" ]; then
  if [ "$reviewed_sha" != "$head_sha" ]; then
    defect "CodeRabbit's review is STALE: it reviewed ${reviewed_sha}, the PR head is ${head_sha}. Commits landed after the review, so the merged tree was never seen. Push-triggered re-review, or '@coderabbitai review'."
  fi
elif [ -s "$bodies" ]; then
  defect "CodeRabbit commented on PR #$PR but never reported a reviewed commit range, so no review of any commit is evidenced. Treat as unreviewed."
fi

# ── Findings, and whether they were dispositioned ─────────────────────────────
if [ "$OFFLINE" -eq 1 ]; then
  inline="$INLINE_OVERRIDE"
else
  inline=$(gh api "repos/$REPO/pulls/$PR/comments" --paginate \
    --jq '[.[] | select(.user.login=="coderabbitai[bot]")] | length' 2>/dev/null)
fi
[ -n "$inline" ] || inline=0
actionable=$(grep -oE 'Actionable comments posted: *[0-9]+' "$bodies" 2>/dev/null \
  | tail -1 | grep -oE '[0-9]+$')
[ -n "$actionable" ] || actionable=0

findings=$inline
[ "$actionable" -gt "$findings" ] 2>/dev/null && findings=$actionable

if [ "$findings" -gt 0 ] 2>/dev/null; then
  # Adjudication, mirroring the BLOCKER-EVENT ledger: the Conductor records a
  # disposition keyed to the head it applies to. Nothing else clears findings.
  disposed=0
  if [ -n "$LOG_MD" ] && [ -r "$LOG_MD" ]; then
    grep -F 'CODERABBIT-EVENT:' "$LOG_MD" 2>/dev/null | grep -Fq "\"head\":\"$head_sha\"" && disposed=1
  fi
  if [ "$disposed" -ne 1 ]; then
    defect "CodeRabbit posted $findings actionable finding(s) on PR #$PR and none are dispositioned for head ${head_sha}. Address them, or record an explicit overrule, then append to log.md: CODERABBIT-EVENT: {\"head\":\"$head_sha\",\"findings\":$findings,\"disposition\":\"addressed|overruled\",\"note\":\"<why>\"}"
  fi
fi

if [ -s "$DEFECTS" ]; then
  cat "$DEFECTS"
  exit 1
fi

echo "coderabbit: clean (reviewed ${head_sha}, ${findings} finding(s) dispositioned or none)"
exit 0
