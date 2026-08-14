name: Delegate affordability uses live Opus percentRemaining and has one mapped Bootstrap call
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/afford-live.XXXXXX")" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/curl" <<'STUB'
  #!/bin/sh
  out=""
  url=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) out="$2"; shift 2 ;;
      -w) shift 2 ;;
      --max-time) shift 2 ;;
      -s) shift ;;
      *) url="$1"; shift ;;
    esac
  done
  [ "$url" = "http://usage.test/opus" ] || exit 64
  printf '%s\n' "$url" >> "$AFFORD_TEST_CALLS"
  printf '{"percentRemaining":%s,"lastUpdated":"stale-is-allowed"}' \
    "$AFFORD_TEST_PERCENT" > "$out"
  printf '200'
  STUB
  chmod +x "$tmp/bin/curl"

  helper="$(grep -v '^[[:space:]]*#' "$ROOT/scripts/resolve-delegate-affordability.sh")"
  printf '%s\n' "$helper" | grep -Fq 'curl -s --max-time 2 -o "$body_file" -w' || exit 1
  printf '%s\n' "$helper" | grep -Fq '"$base_url/opus"' || exit 1

  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md")"
  [ "$(printf '%s\n' "$bootstrap" | grep -c 'scripts/resolve-delegate-affordability.sh')" -eq 1 ] || exit 1
  seam="$tmp/delegate-affordability-selection.sh"
  printf '%s\n' "$bootstrap" | awk \
    '/DELEGATE-AFFORDABILITY-SELECTION:BEGIN/{on=1; next}
     /DELEGATE-AFFORDABILITY-SELECTION:END/{on=0}
     on' > "$seam"
  [ -s "$seam" ] || exit 1

  run_case() {
    case_name="$1"
    percent="$2"
    expected_model="$3"
    case_dir="$tmp/$case_name"
    mkdir -p "$case_dir/run" "$case_dir/home/.novadiem"
    printf '%s\n' '{"runtime":"claude","roles":{"conductor":{"model":"opus","reasoningEffort":"high"}}}' \
      > "$case_dir/run/model-routing.json"
    : > "$case_dir/calls"
    observed="$(
      ROOT="$ROOT" SEAM="$seam" RUN_DIR="$case_dir/run" HOME="$case_dir/home" \
      PATH="$tmp/bin:$PATH" CLAUDE_USAGE_BASE_URL=http://usage.test \
      AFFORD_TEST_CALLS="$case_dir/calls" AFFORD_TEST_PERCENT="$percent" \
      /bin/sh -c '
        cd "$ROOT" || exit 1
        conductor_tokens=conductor-sentinel
        delegate_tokens=delegate-sentinel
        reviewer_tokens=reviewer-sentinel
        processed_total=processed-sentinel
        . "$SEAM" || exit 1
        printf "%s|%s|%s|%s|%s" \
          "$_delegate_conductor_model" "$conductor_tokens" "$delegate_tokens" \
          "$reviewer_tokens" "$processed_total"
      '
    )" || exit 1
    [ "$observed" = "$expected_model|conductor-sentinel|delegate-sentinel|reviewer-sentinel|processed-sentinel" ] || exit 1
    [ "$(wc -l < "$case_dir/calls" | tr -d ' ')" -eq 1 ] || exit 1
    [ "$(cat "$case_dir/calls")" = "http://usage.test/opus" ] || exit 1
  }

  run_case high 61.5 opus
  [ ! -s "$tmp/high/run/log.md" ] || exit 1

  run_case low 10 sonnet
  [ "$(wc -l < "$tmp/low/run/log.md" | tr -d ' ')" -eq 1 ] || exit 1
  override="$(sed -n 's/^MODEL-OVERRIDE: //p' "$tmp/low/run/log.md")"
  printf '%s' "$override" | jq -e '
    .role == "conductor" and
    .attempt_id == "conductor-bootstrap-1" and
    .configured == "opus" and
    .actual == "sonnet" and
    (.reason | contains("affordability") and contains("budget_pressure")) and
    (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (has("percent_remaining") | not) and
    (has("conductor_tokens") | not) and
    (has("delegate_tokens") | not) and
    (has("reviewer_tokens") | not) and
    (has("processed_total") | not)
  ' >/dev/null || exit 1

  printf '%s\n' "$bootstrap" | grep -Fq 'Set `model` explicitly to the already-derived' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq '`$_delegate_conductor_model` (do not re-read `roles.conductor.model` at spawn time)' || exit 1
expected: exits 0 only when the shipped Bootstrap seam calls live /opus once, selects configured opus at 61.5 and sonnet at 10, audits only the downgrade, preserves accounting sentinels, and passes the derived model to spawn
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
