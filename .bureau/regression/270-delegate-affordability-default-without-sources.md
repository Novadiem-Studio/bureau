name: Delegate affordability defaults when live and snapshot sources are unavailable
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/afford-default.XXXXXX")" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/curl" <<'STUB'
  #!/bin/sh
  out=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) out="$2"; shift 2 ;;
      -w) shift 2 ;;
      --max-time) shift 2 ;;
      -s) shift ;;
      *) shift ;;
    esac
  done
  case "${CURL_SCENARIO:-}" in
    nonnumeric)
      printf '%s' '{"percentRemaining":"not-numeric"}' > "$out"
      printf '200'
      exit 0
      ;;
    trailing)
      printf '%s' '{"percentRemaining":10} trailing-garbage' > "$out"
      printf '200'
      exit 0
      ;;
  esac
  printf '000'
  exit 7
  STUB
  chmod +x "$tmp/bin/curl"
  actual="$(PATH="$tmp/bin:$PATH" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/absent.json")" || exit 1
  [ "$actual" = '{"action":"default","source":"none"}' ] || exit 1
  printf '%s\n' '{"claude":{"weeklyLeftPercent":"not-numeric"}}' > "$tmp/nonnumeric-snapshot.json"
  actual="$(PATH="$tmp/bin:$PATH" CURL_SCENARIO=nonnumeric CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/nonnumeric-snapshot.json")" || exit 1
  [ "$actual" = '{"action":"default","source":"none"}' ] || exit 1
  printf '%s\n' '{"claude":{"weeklyLeftPercent":61.5}}' > "$tmp/valid-snapshot.json"
  actual="$(PATH="$tmp/bin:$PATH" CURL_SCENARIO=trailing CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/valid-snapshot.json")" || exit 1
  [ "$actual" = '{"action":"use_quota","source":"snapshot","percent_remaining":61.5}' ] || exit 1
  printf '%s\n' '{"claude":{"weeklyLeftPercent":10}} trailing-garbage' > "$tmp/trailing-snapshot.json"
  actual="$(PATH="$tmp/bin:$PATH" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/trailing-snapshot.json")" || exit 1
  [ "$actual" = '{"action":"default","source":"none"}' ] || exit 1
  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md" | grep -v '^[[:space:]]*#')"
  printf '%s\n' "$bootstrap" | grep -Fq 'For `action:"default"`, follow the normal default-model' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq 'must never block startup' || exit 1
  mkdir -p "$tmp/bootstrap/scripts" "$tmp/bootstrap/run" "$tmp/bootstrap/home/.novadiem"
  cat > "$tmp/bootstrap/scripts/resolve-delegate-affordability.sh" <<'STUB'
  #!/bin/sh
  printf '%s\n' '{"action":"use_quota","source":"live","percent_remaining":10} trailing-garbage'
  STUB
  chmod +x "$tmp/bootstrap/scripts/resolve-delegate-affordability.sh"
  printf '%s\n' '{"runtime":"claude","roles":{"conductor":{"model":"opus"}}}' > "$tmp/bootstrap/run/model-routing.json"
  awk '
    /DELEGATE-AFFORDABILITY-SELECTION:BEGIN/ { on=1; next }
    /DELEGATE-AFFORDABILITY-SELECTION:END/ { on=0 }
    on
  ' "$ROOT/agents/delegate.md" > "$tmp/bootstrap/selection.sh"
  (
    cd "$tmp/bootstrap" || exit 1
    RUN_DIR="$tmp/bootstrap/run"
    HOME="$tmp/bootstrap/home"
    export RUN_DIR HOME
    . "$tmp/bootstrap/selection.sh" || exit 1
    [ "$_delegate_conductor_configured_model" = "opus" ] || exit 1
    [ "$_delegate_conductor_model" = "opus" ] || exit 1
    [ ! -e "$RUN_DIR/log.md" ] || ! grep -Fq 'MODEL-OVERRIDE:' "$RUN_DIR/log.md"
  ) || exit 1
expected: exits 0 only when absent or unparseable live and snapshot inputs emit default/none and Bootstrap preserves startup/default routing
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
