name: Delegate affordability skips all live quota work on OpenAI runtime
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/afford-openai.XXXXXX")" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/curl" <<'STUB'
  #!/bin/sh
  : > "$CURL_ATTEMPT_MARKER"
  exit 99
  STUB
  chmod +x "$tmp/bin/curl"
  marker="$tmp/curl-attempted"
  actual="$(PATH="$tmp/bin:$PATH" CURL_ATTEMPT_MARKER="$marker" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" openai "$tmp/absent.json")" || exit 1
  [ "$actual" = '{"action":"skip","source":"runtime"}' ] || exit 1
  [ ! -e "$marker" ] || exit 1
  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md" | grep -v '^[[:space:]]*#')"
  printf '%s\n' "$bootstrap" | grep -Fq 'For `action:"skip"`, take no quota action.' || exit 1
expected: exits 0 only when OpenAI emits skip/runtime, never invokes curl, and maps to no quota action
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
