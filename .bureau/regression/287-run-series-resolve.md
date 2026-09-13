name: run-series-resolve finds INDEX in a plan dir or a campaign parent
phase: envoy run-series
owner: scripts/run-series-resolve.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  cleanup() { rm -rf "$TMPF"; }
  trap cleanup EXIT INT TERM

  CAMPAIGN="$TMPF/campaign"
  PLAN="$CAMPAIGN/build-plan"
  mkdir -p "$PLAN"
  printf '# index\n' > "$PLAN/INDEX.md"
  printf '# charter\n' > "$CAMPAIGN/SUPERVISOR.md"
  printf '# state\n' > "$CAMPAIGN/SUPERVISOR-STATE.md"
  printf '# handoff\n' > "$CAMPAIGN/HANDOFF.md"
  PLAN_ABS="$(cd "$PLAN" && pwd -P)"
  CAMPAIGN_ABS="$(cd "$CAMPAIGN" && pwd -P)"

  out_plan="$("$ROOT/scripts/run-series-resolve.sh" "$PLAN")"
  printf '%s\n' "$out_plan" | grep -Fq "PLAN_DIR=$PLAN_ABS" \
    || { echo "FAIL: plan-dir pointer missed PLAN_DIR"; exit 1; }
  printf '%s\n' "$out_plan" | grep -Fq "CAMPAIGN_DIR=$CAMPAIGN_ABS" \
    || { echo "FAIL: plan-dir pointer missed CAMPAIGN_DIR"; exit 1; }
  printf '%s\n' "$out_plan" | grep -Fq "CHARTER=$CAMPAIGN_ABS/SUPERVISOR.md" \
    || { echo "FAIL: charter not resolved from parent"; exit 1; }

  out_camp="$("$ROOT/scripts/run-series-resolve.sh" "$CAMPAIGN")"
  printf '%s\n' "$out_camp" | grep -Fq "PLAN_DIR=$PLAN_ABS" \
    || { echo "FAIL: campaign pointer missed nested build-plan"; exit 1; }
  printf '%s\n' "$out_camp" | grep -Fq "CAMPAIGN_DIR=$CAMPAIGN_ABS" \
    || { echo "FAIL: campaign pointer missed CAMPAIGN_DIR"; exit 1; }

  empty="$TMPF/empty"
  mkdir -p "$empty"
  if "$ROOT/scripts/run-series-resolve.sh" "$empty" >/dev/null 2>"$TMPF/err"; then
    echo "FAIL: empty dir should exit 1"; exit 1
  fi

  echo PASS
expected: exit 0; stdout "PASS"; plan dir and campaign dir both resolve INDEX + charter; missing INDEX exits 1.
