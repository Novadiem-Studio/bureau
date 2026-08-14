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
  if [ "${CURL_SCENARIO:-}" = "malformed" ]; then
    printf '%s' '{"percentRemaining":"not-numeric"}' > "$out"
    printf '200'
    exit 0
  fi
  printf '000'
  exit 7
  STUB
  chmod +x "$tmp/bin/curl"
  actual="$(PATH="$tmp/bin:$PATH" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/absent.json")" || exit 1
  [ "$actual" = '{"action":"default","source":"none"}' ] || exit 1
  printf '%s\n' '{"claude":{"weeklyLeftPercent":"not-numeric"}}' > "$tmp/malformed-snapshot.json"
  actual="$(PATH="$tmp/bin:$PATH" CURL_SCENARIO=malformed CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/malformed-snapshot.json")" || exit 1
  [ "$actual" = '{"action":"default","source":"none"}' ] || exit 1
  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md" | grep -v '^[[:space:]]*#')"
  printf '%s\n' "$bootstrap" | grep -Fq 'For `action:"default"`, follow the normal default-model' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq 'must never block startup' || exit 1
expected: exits 0 only when absent or unparseable live and snapshot inputs emit default/none and Bootstrap preserves startup/default routing
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
