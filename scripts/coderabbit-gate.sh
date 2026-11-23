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
#   --inline-file FILE     the PR's inline review comments as the API returns them
#                          (a JSON array), or instead:
#   --inline-count N       N inline findings with no ids (they can never be dispositioned,
#                          so N > 0 always fails; N = 0 means none)
#   --reviews-file FILE    optional; the PR's formal reviews as the API returns them
#                          (a JSON array; default []). Offline mode only.
#
# Findings are dispositioned BY ID (#146). The open set is every top-level inline comment
# by coderabbitai[bot] (its numeric comment id) plus every entry in the "Outside diff range
# comments (N)" section of a bot review on the head (id b<review id>-<first 12 hex of the
# sha256 of "<file:lines>|<title>">). Each must be named in the `ids` of a CODERABBIT-EVENT
# for the head; a count never clears anything. The gate prints the open ids.
#
# Exit codes (mirrors preflight-artifacts.sh / spawn-gate.sh):
#   0  + "coderabbit: clean"   reviewed at the current head; findings zero or dispositioned
#   1  + DEFECT line(s)        not reviewed, stale, or findings left undispositioned
#   2                          cannot run (bad args, no PR recorded, gh/jq missing)
#
# WHY THIS EXISTS. CodeRabbit usually posts as an ISSUE COMMENT from coderabbitai[bot],
# not a formal review: `gh pr view --json reviews` returns [] and reviewDecision is "".
# pr-delivery.sh's `reviewDecision != CHANGES_REQUESTED` check therefore cannot see
# a CodeRabbit finding. This gate reads the bot's comments directly instead. When the
# summary reports no range (auto-review paused, or after '@coderabbitai resume'), a
# formal review from the bot whose commit_id is the head is accepted as the proof (#146).
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
COMMENTS_FILE=""; HEAD_OVERRIDE=""; INLINE_OVERRIDE=""; REVIEWS_FILE=""; INLINE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reviews-file)  REVIEWS_FILE="$2";    shift 2 ;;
    --inline-file)   INLINE_FILE="$2";     shift 2 ;;
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
if [ -n "$COMMENTS_FILE" ] || [ -n "$HEAD_OVERRIDE" ] || [ -n "$INLINE_OVERRIDE" ] || [ -n "$INLINE_FILE" ]; then
  if [ -z "$COMMENTS_FILE" ] || [ -z "$HEAD_OVERRIDE" ] || { [ -z "$INLINE_OVERRIDE" ] && [ -z "$INLINE_FILE" ]; }; then
    echo "coderabbit-gate: --comments-file, --head and --inline-file (or --inline-count) must be given together" >&2
    exit 2
  fi
  if [ -n "$INLINE_OVERRIDE" ] && [ -n "$INLINE_FILE" ]; then
    echo "coderabbit-gate: give --inline-file or --inline-count, not both" >&2; exit 2
  fi
  [ -r "$COMMENTS_FILE" ] || { echo "coderabbit-gate: unreadable --comments-file" >&2; exit 2; }
  [ -z "$INLINE_FILE" ] || [ -r "$INLINE_FILE" ] || { echo "coderabbit-gate: unreadable --inline-file" >&2; exit 2; }
  case "$INLINE_OVERRIDE" in *[!0-9]*) echo "coderabbit-gate: --inline-count must be a whole number" >&2; exit 2 ;; esac
  OFFLINE=1
  [ -n "$REPO" ] || REPO="offline/offline"
  [ -n "$PR" ] || PR="0"
fi
if [ -n "$REVIEWS_FILE" ]; then
  [ "$OFFLINE" -eq 1 ] || { echo "coderabbit-gate: --reviews-file needs the offline seam (--comments-file, --head, --inline-file or --inline-count)" >&2; exit 2; }
  [ -r "$REVIEWS_FILE" ] || { echo "coderabbit-gate: unreadable --reviews-file" >&2; exit 2; }
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
  # The skip marker is OVERLOADED — CodeRabbit emits it for several unrelated
  # causes (draft PR; repo under the free tier's 10-star threshold; auto-review
  # disabled). Quote its own stated reason rather than guessing one: an earlier
  # version of this gate asserted "draft PR" and was wrong on a non-draft PR that
  # had simply fallen under the star threshold.
  skip_reason=$(grep -oE 'This repository does not receive automatic reviews[^<]*|Draft PRs are not automatically reviewed[^<]*|Review limit reached[^<]*' "$bodies" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  if [ -n "$skip_reason" ]; then
    defect "CodeRabbit SKIPPED the review. Its stated reason: \"$skip_reason\" Nothing was reviewed, so this PR has no CodeRabbit verdict. Re-trigger with an '@coderabbitai review' PR comment, or remove the cause."
  else
    defect "CodeRabbit SKIPPED the review and gave no parseable reason — read its comment on the PR. Nothing was reviewed. Common causes: a draft PR (Bureau opens every PR with --draft, so set reviews.auto_review.drafts: true in the target repo's .coderabbit.yaml), or the repo falling under the free tier's automatic-review threshold."
  fi
fi
if grep -q 'rate limited by coderabbit.ai' "$bodies" 2>/dev/null; then
  defect "CodeRabbit was RATE LIMITED and did not review (plan limit or exhausted credits). Re-trigger with an '@coderabbitai review' PR comment once capacity returns; do not merge on the assumption it passed."
fi

# ── The PR's formal reviews (no-range proof, and body-only findings) ──────────
# A failed or unreadable lookup is an error: body-only findings live here, so a gate that
# cannot read them cannot pass.
reviews="$WORK/reviews.json"
if [ "$OFFLINE" -eq 1 ]; then
  if [ -n "$REVIEWS_FILE" ]; then cp "$REVIEWS_FILE" "$reviews"; else echo '[]' > "$reviews"; fi
else
  if ! gh api "repos/$REPO/pulls/$PR/reviews" --paginate --jq '.[]' > "$WORK/reviews.lines" 2>"$WORK/reviews.err"; then
    echo "coderabbit-gate: cannot read formal reviews for PR #$PR in $REPO: $(head -1 "$WORK/reviews.err")" >&2
    exit 2
  fi
  jq -s '.' "$WORK/reviews.lines" > "$reviews" 2>/dev/null || : > "$reviews"
fi
if ! jq -e 'type == "array"' "$reviews" >/dev/null 2>&1; then
  echo "coderabbit-gate: unreadable formal reviews for PR #$PR in $REPO" >&2
  exit 2
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
  # No range in the summary (auto-review paused, or after '@coderabbitai resume'). A formal
  # review by the bot on exactly this head is the proof instead; one on another commit, or
  # by another login, is not (#146).
  review_shas="$WORK/review-shas.txt"
  jq -r '.[] | select(.user.login=="coderabbitai[bot]") | .commit_id // empty' "$reviews" > "$review_shas" 2>/dev/null
  if ! grep -Fxq "$head_sha" "$review_shas" 2>/dev/null; then
    defect "CodeRabbit commented on PR #$PR but never reported a reviewed commit range, and has no formal review on head ${head_sha}, so no review of this head is evidenced. Treat as unreviewed."
  fi
fi

# ── Findings, by id, and whether each was dispositioned ───────────────────────
# Open inline findings: top-level comments by the bot (a reply in a thread is not a new
# finding), across every commit, each by its numeric comment id. A failed or unreadable
# lookup is an error, not zero findings: a gate that cannot list findings cannot pass.
open_ids="$WORK/open-ids.txt"; : > "$open_ids"
INLINE_JQ='.[] | select(.user.login == "coderabbitai[bot]" and (.in_reply_to_id // null) == null) | .id'
anon=0
if [ "$OFFLINE" -eq 1 ] && [ -n "$INLINE_OVERRIDE" ]; then
  anon="$INLINE_OVERRIDE"
elif [ "$OFFLINE" -eq 1 ]; then
  jq -r "$INLINE_JQ" "$INLINE_FILE" > "$WORK/inline.ids" 2>/dev/null \
    || { echo "coderabbit-gate: unreadable --inline-file" >&2; exit 2; }
else
  if ! gh api "repos/$REPO/pulls/$PR/comments" --paginate --jq "$INLINE_JQ" > "$WORK/inline.ids" 2>"$WORK/inline.err"; then
    echo "coderabbit-gate: cannot read inline review comments for PR #$PR in $REPO: $(head -1 "$WORK/inline.err")" >&2
    exit 2
  fi
fi
if [ -s "$WORK/inline.ids" ]; then
  if grep -vqE '^[0-9]+$' "$WORK/inline.ids"; then
    echo "coderabbit-gate: unreadable inline review comment ids for PR #$PR in $REPO" >&2
    exit 2
  fi
  cat "$WORK/inline.ids" >> "$open_ids"
fi
if [ "$anon" -gt 0 ]; then
  defect "$anon inline finding(s) on PR #$PR were given only as a count (--inline-count), with no ids, so none can be dispositioned. Use --inline-file."
fi

# Body-only findings: entries in the "Outside diff range comments (N)" section of a bot
# review on the head have no comment id. Each gets b<review id>-<12 hex of the sha256 of
# "<file:lines>|<title>">. If the N entries cannot all be parsed, fail closed.
jq -r --arg h "$head_sha" '
  .[] | select(.user.login == "coderabbitai[bot]" and .commit_id == $h) | . as $r
  | (($r.body // "") | split("\n")) as $L
  | ([$L | to_entries[] | select(.value | test("Outside diff range comments \\([0-9]+\\)")) | .key] | first) as $i
  | select($i != null)
  | ($L[$i] | capture("Outside diff range comments \\((?<n>[0-9]+)\\)").n | tonumber) as $n
  | ([$L | to_entries[] | select(.key > $i and (.value | startswith(">") | not)) | .key] | first // ($L | length)) as $k
  | [$L[$i + 1:$k][] | select(test("^> *<summary><strong>"))
     | (capture(" · (?<title>.+) · <code>(?<loc>[^<]+)</code></summary>") // null)] as $e
  | if ($e | length) == $n and all($e[]; . != null)
    then ($e[] | ["ID", ($r.id | tostring), .loc, .title] | @tsv)
    else ["BAD", ($r.id | tostring), ($n | tostring), ([$e[] | select(. != null)] | length | tostring)] | @tsv
    end' "$reviews" > "$WORK/body.tsv" 2>/dev/null \
  || { echo "coderabbit-gate: cannot parse formal review bodies for PR #$PR in $REPO" >&2; exit 2; }
tab=$(printf '\t')
while IFS="$tab" read -r kind rid f3 f4; do
  case "$kind" in
    ID)  printf 'b%s-%s\n' "$rid" "$(printf '%s|%s' "$f3" "$f4" | shasum -a 256 | cut -c1-12)" >> "$open_ids" ;;
    BAD) defect "CodeRabbit review $rid on head ${head_sha} lists \"Outside diff range comments ($f3)\" but only $f4 entr(ies) could be parsed, so those findings have no reliable ids and cannot be dispositioned. Read the review body; this gate fails closed until it parses." ;;
  esac
done < "$WORK/body.tsv"

# A summary that claims more actionable comments than there are finding ids leaves some
# finding unnamed; fail closed rather than guess which.
total=$(grep -c . "$open_ids")
actionable=$(grep -oE 'Actionable comments posted: *[0-9]+' "$bodies" 2>/dev/null \
  | tail -1 | grep -oE '[0-9]+$')
[ -n "$actionable" ] || actionable=0
if [ "$actionable" -gt $((total + anon)) ]; then
  defect "CodeRabbit reports $actionable actionable comment(s) on PR #$PR but only $((total + anon)) finding id(s) were found, so some findings cannot be named. Read the PR's review comments."
fi

if [ "$total" -gt 0 ]; then
  # Adjudication, mirroring the BLOCKER-EVENT ledger: an event for exactly this head, with
  # disposition addressed or overruled, names the finding ids it covers. Ids compare as
  # strings, so 4662945345 and "4662945345" match. A count (`findings`) clears nothing.
  disposed="$WORK/disposed-ids.txt"; : > "$disposed"
  if [ -n "$LOG_MD" ] && [ -r "$LOG_MD" ]; then
    grep -F 'CODERABBIT-EVENT:' "$LOG_MD" 2>/dev/null \
      | sed 's/^.*CODERABBIT-EVENT:[[:space:]]*//' \
      | jq -nrR --arg h "$head_sha" '
          inputs | (try fromjson catch null)
          | select(type == "object" and .head == $h
                   and (.disposition == "addressed" or .disposition == "overruled"))
          | .ids | select(type == "array") | .[]
          | select(type == "string" or type == "number") | tostring' > "$disposed" 2>/dev/null
  fi
  # FILENAME, not NR == FNR: with no dispositions the first file is empty, and NR == FNR
  # would then read the open ids as dispositioned.
  awk 'FILENAME == ARGV[1] { done[$0] = 1; next } !($0 in done) && !seen[$0]++' "$disposed" "$open_ids" > "$WORK/undisposed.txt"
  if [ -s "$WORK/undisposed.txt" ]; then
    n_open=$(grep -c . "$WORK/undisposed.txt")
    list=$(tr '\n' ' ' < "$WORK/undisposed.txt" | sed 's/ $//')
    ids_json=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$WORK/undisposed.txt")
    defect "CodeRabbit has $n_open of $total finding(s) on PR #$PR not dispositioned for head ${head_sha} (open: $list). Address or overrule each, then append to log.md: CODERABBIT-EVENT: {\"head\":\"$head_sha\",\"disposition\":\"addressed|overruled\",\"ids\":$ids_json,\"note\":\"<why>\"}"
  fi
fi

if [ -s "$DEFECTS" ]; then
  cat "$DEFECTS"
  exit 1
fi

echo "coderabbit: clean (reviewed ${head_sha}, ${total} finding(s), each dispositioned by id, or none)"
exit 0
