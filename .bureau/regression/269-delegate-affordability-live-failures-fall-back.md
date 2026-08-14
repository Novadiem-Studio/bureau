name: Delegate affordability maps 503, refusal, and timeout to the readable snapshot
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/afford-fallback.XXXXXX")" || exit 1
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
    503) printf '%s' '{"error":"unavailable","message":"no cached usage"}' > "$out"; printf '503'; exit 0 ;;
    refused) printf '000'; exit 7 ;;
    timeout) printf '000'; exit 28 ;;
    *) exit 64 ;;
  esac
  STUB
  chmod +x "$tmp/bin/curl"
  printf '%s\n' '{"claude":{"weeklyLeftPercent":38}}' > "$tmp/snapshot.json"
  expected='{"action":"use_quota","source":"snapshot","percent_remaining":38}'
  for scenario in 503 refused timeout; do
    actual="$(PATH="$tmp/bin:$PATH" CURL_SCENARIO="$scenario" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/snapshot.json")" || exit 1
    [ "$actual" = "$expected" ] || exit 1
  done
expected: exits 0 only when 503, refused, and timeout cases all emit the exact use_quota/snapshot disposition
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
