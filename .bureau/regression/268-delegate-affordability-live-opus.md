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
  printf '%s' '{"percentRemaining":61.5,"lastUpdated":"stale-is-allowed"}' > "$out"
  printf '200'
  STUB
  chmod +x "$tmp/bin/curl"
  actual="$(PATH="$tmp/bin:$PATH" CLAUDE_USAGE_BASE_URL=http://usage.test "$ROOT/scripts/resolve-delegate-affordability.sh" claude "$tmp/missing.json")" || exit 1
  [ "$actual" = '{"action":"use_quota","source":"live","percent_remaining":61.5}' ] || exit 1
  helper="$(grep -v '^[[:space:]]*#' "$ROOT/scripts/resolve-delegate-affordability.sh")"
  printf '%s\n' "$helper" | grep -Fq 'curl -s --max-time 2 -o "$body_file" -w' || exit 1
  printf '%s\n' "$helper" | grep -Fq '"$base_url/opus"' || exit 1
  bootstrap="$(awk '/^### Bootstrap$/{on=1} /^### Main manager loop$/{on=0} on' "$ROOT/agents/delegate.md" | grep -v '^[[:space:]]*#')"
  [ "$(printf '%s\n' "$bootstrap" | grep -c 'scripts/resolve-delegate-affordability.sh')" -eq 1 ] || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq '"$_delegate_affordability_runtime" "$HOME/.novadiem/usage-snapshot.json"' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq '`action:"use_quota"`, use `percent_remaining` as the affordability input' || exit 1
  printf '%s\n' "$bootstrap" | grep -Fq 'Claude opus-vs-sonnet model decision' || exit 1
expected: exits 0 only when bounded live numeric /opus emits use_quota/live and the Delegate maps one helper call into model choice
phase: 08 · execute-plan
owner: Prompt 08 — Phase 3 FR6 affordability wiring
