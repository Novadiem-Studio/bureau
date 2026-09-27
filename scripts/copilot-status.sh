#!/usr/bin/env bash
# copilot-status.sh — one-screen view of GitHub Copilot cloud-agent spend and work.
#
# Usage:
#   copilot-status.sh            # print the report
#   copilot-status.sh --alerts   # print only what needs Robin; exit 0 silent when nothing does
#   copilot-status.sh --json     # machine-readable snapshot on stdout
#
# Reads:
#   GET /users/{u}/settings/billing/usage/summary  (needs the gh `user` scope)
#   gh search prs --author app/copilot-swe-agent   (open agent PRs across OWNERS)
#
# Writes one snapshot line per run to ~/.novadiem/copilot-usage.jsonl, so the
# per-task cost of a session is the credit delta between two snapshots. The
# billing API reports Copilot Cloud Agent credits as one aggregate SKU, with no
# per-model or per-repo split; the web "AI usage" page is the only per-model view.
#
# Env:
#   COPILOT_INCLUDED_CREDITS  monthly included AI credits (default 1500, Copilot Pro)
#   COPILOT_OWNERS            space-separated owners to scan (default "rheos Novadiem-Studio")
#   COPILOT_ALERT_PCT         alert when remaining credits fall below this % (default 20)

set -u
set -o pipefail

INCLUDED="${COPILOT_INCLUDED_CREDITS:-1500}"
OWNERS="${COPILOT_OWNERS:-rheos Novadiem-Studio}"
ALERT_PCT="${COPILOT_ALERT_PCT:-20}"
STATE_DIR="${HOME}/.novadiem"
LOG_FILE="${STATE_DIR}/copilot-usage.jsonl"

mode="report"
case "${1:-}" in
  --alerts) mode="alerts" ;;
  --json) mode="json" ;;
  "") ;;
  *) echo "copilot-status: unknown flag $1" >&2; exit 2 ;;
esac

gh_login="$(gh api user --jq .login)" || { echo "copilot-status: gh not authenticated" >&2; exit 1; }

summary="$(gh api "/users/${gh_login}/settings/billing/usage/summary" 2>/dev/null)" || {
  echo "copilot-status: billing summary unavailable; run: gh auth refresh -h github.com -s user" >&2
  exit 1
}

credits_used="$(jq -r '[.usageItems[] | select(.product=="Copilot") | .grossQuantity] | add // 0' <<<"$summary")"
actions_min="$(jq -r '[.usageItems[] | select(.product=="Actions") | .grossQuantity] | add // 0' <<<"$summary")"
actions_net="$(jq -r '[.usageItems[] | .netAmount] | add // 0' <<<"$summary")"

# Days until the first of next month (credits reset then).
today_epoch="$(date +%s)"
next_month="$(date -v+1m -v1d +%Y-%m-01 2>/dev/null || date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-%d)"
reset_epoch="$(date -j -f %Y-%m-%d "$next_month" +%s 2>/dev/null || date -d "$next_month" +%s)"
days_left=$(( (reset_epoch - today_epoch + 86399) / 86400 ))

owner_args=()
for o in $OWNERS; do owner_args+=(--owner "$o"); done
prs="$(gh search prs --author app/copilot-swe-agent "${owner_args[@]}" --state open \
  --json repository,number,title,isDraft,url --limit 50 2>/dev/null || echo '[]')"

# Enrich each PR with size and CI rollup.
pr_rows="[]"
while IFS= read -r pr; do
  [ -n "$pr" ] || continue
  repo="$(jq -r .repository.nameWithOwner <<<"$pr")"
  num="$(jq -r .number <<<"$pr")"
  detail="$(gh pr view "$num" -R "$repo" --json additions,deletions,changedFiles,statusCheckRollup,reviewDecision 2>/dev/null || echo '{}')"
  row="$(jq -n --argjson p "$pr" --argjson d "$detail" '
    ($d.statusCheckRollup // []) as $c
    | {repo: $p.repository.nameWithOwner, number: $p.number, title: $p.title,
       draft: $p.isDraft, url: $p.url,
       additions: ($d.additions // 0), deletions: ($d.deletions // 0), files: ($d.changedFiles // 0),
       ci: (if ($c|length)==0 then "none"
            elif any($c[]; (.conclusion // .state) | IN("FAILURE","ERROR","CANCELLED","TIMED_OUT")) then "failing"
            elif any($c[]; (.status // "") | IN("IN_PROGRESS","QUEUED","PENDING")) then "running"
            else "passing" end),
       review: ($d.reviewDecision // "")}')"
  pr_rows="$(jq --argjson r "$row" '. + [$r]' <<<"$pr_rows")"
done < <(jq -c '.[]' <<<"$prs")

snapshot="$(jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson used "$credits_used" --argjson included "$INCLUDED" \
  --argjson actions "$actions_min" --argjson net "$actions_net" \
  --argjson days "$days_left" --argjson prs "$pr_rows" '
  {ts: $ts, credits_used: $used, credits_included: $included,
   credits_left: ($included - $used), days_to_reset: $days,
   actions_minutes: $actions, net_billed_usd: $net, open_agent_prs: $prs}')"

mkdir -p "$STATE_DIR"
jq -c 'del(.open_agent_prs) + {open_prs: (.open_agent_prs|length)}' <<<"$snapshot" >>"$LOG_FILE"

# Credits spent since the previous snapshot (the first run has no delta).
prev_used="$(tail -n 2 "$LOG_FILE" | head -n 1 | jq -r .credits_used)"
line_count="$(wc -l <"$LOG_FILE" | tr -d ' ')"
delta="$(jq -n --argjson a "$credits_used" --argjson b "$prev_used" '($a - $b) * 100 | round / 100')"

if [ "$mode" = "json" ]; then
  printf '%s\n' "$snapshot"
  exit 0
fi

left_pct="$(jq -n --argjson u "$credits_used" --argjson i "$INCLUDED" '(($i - $u) / $i * 100) | floor')"

if [ "$mode" = "alerts" ]; then
  alerts=()
  if [ "$left_pct" -lt "$ALERT_PCT" ] && [ "$days_left" -gt 3 ]; then
    alerts+=("Copilot credits at ${left_pct}% with ${days_left} days to reset")
  fi
  if [ "$(jq -n --argjson n "$actions_net" '$n > 0')" = "true" ]; then
    alerts+=("GitHub is now billing overage: \$${actions_net} net this month")
  fi
  while IFS= read -r r; do [ -n "$r" ] && alerts+=("$r"); done < <(jq -r '.[] |
    if .draft == false and .review == "" then "Ready for review: \(.repo)#\(.number) \(.title)"
    elif .ci == "failing" then "CI failing: \(.repo)#\(.number) \(.title)"
    else empty end' <<<"$pr_rows")
  [ "${#alerts[@]}" -eq 0 ] && exit 0
  printf '%s\n' "${alerts[@]}"
  exit 0
fi

printf 'Copilot credits  %s / %s used  (%s%% left, resets in %s days)\n' \
  "$(printf '%.1f' "$credits_used")" "$INCLUDED" "$left_pct" "$days_left"
if [ "$line_count" -gt 1 ]; then
  printf '  since last run  %s credits\n' "$delta"
fi
printf 'Actions minutes  %s this month  (net billed $%s)\n' "$(printf '%.0f' "$actions_min")" "$actions_net"
printf '\nOpen Copilot PRs\n'
jq -r 'if length == 0 then "  none" else .[] |
  "  \(.repo)#\(.number)  \(if .draft then "draft" else "READY" end)  ci=\(.ci)  +\(.additions)/-\(.deletions) in \(.files)  \(.title)" end' <<<"$pr_rows"
