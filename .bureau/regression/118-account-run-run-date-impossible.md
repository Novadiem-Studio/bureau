name: run_date impossible date — stage-2 calendar validation (5 sub-cases)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  STD_STATE='{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{}}'
  mkdir -p "$TMPF/20261301-impossible-month" && printf '%s\n' "$STD_STATE" > "$TMPF/20261301-impossible-month/state.json"
  mkdir -p "$TMPF/20260230-feb30"            && printf '%s\n' "$STD_STATE" > "$TMPF/20260230-feb30/state.json"
  mkdir -p "$TMPF/00001201-year-zero"        && printf '%s\n' "$STD_STATE" > "$TMPF/00001201-year-zero/state.json"
  mkdir -p "$TMPF/20240229-leap-valid"       && printf '%s\n' "$STD_STATE" > "$TMPF/20240229-leap-valid/state.json"
  mkdir -p "$TMPF/20230229-leap-invalid"     && printf '%s\n' "$STD_STATE" > "$TMPF/20230229-leap-invalid/state.json"
  bash "$ROOT/scripts/account-run.sh" "$TMPF/20261301-impossible-month" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.run.run_date.value == null and .run.run_date.confidence == "unavailable"' "$TMPF/20261301-impossible-month/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  bash "$ROOT/scripts/account-run.sh" "$TMPF/20260230-feb30" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.run.run_date.value == null and .run.run_date.confidence == "unavailable"' "$TMPF/20260230-feb30/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  bash "$ROOT/scripts/account-run.sh" "$TMPF/00001201-year-zero" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.run.run_date.value == null and .run.run_date.confidence == "unavailable"' "$TMPF/00001201-year-zero/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  bash "$ROOT/scripts/account-run.sh" "$TMPF/20240229-leap-valid" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.run.run_date.value == "20240229" and .run.run_date.confidence == "exact"' "$TMPF/20240229-leap-valid/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  bash "$ROOT/scripts/account-run.sh" "$TMPF/20230229-leap-invalid" >/dev/null 2>&1 || { rm -rf "$TMPF"; exit 1; }
  jq -e '.run.run_date.value == null and .run.run_date.confidence == "unavailable"' "$TMPF/20230229-leap-invalid/accounting.json" > /dev/null || { rm -rf "$TMPF"; exit 1; }
  rm -rf "$TMPF"
  echo "PASS"
expected: exit 0; stdout "PASS"; run_date {null,unavailable} for impossible-month/feb30/year-zero/leap-invalid; run_date {value:"20240229",exact} for leap-valid
phase: 02 · execute-plan
owner: Prompt 02 / account-run base-engine battle-test (multi-sub-case)
