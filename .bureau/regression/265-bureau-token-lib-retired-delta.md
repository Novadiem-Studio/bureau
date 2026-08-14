name: live-hook delta functions are retired while post-hoc summation and reviewer locking survive
owner: scripts/lib/bureau-token-lib.sh FR4 REPLACE surface
phase: 05 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  bash -c '
    source "$1" || exit 1
    ! declare -F compute_delta_line >/dev/null || exit 1
    ! declare -F compute_legacy_line >/dev/null || exit 1
    declare -F sum_transcript_usage >/dev/null || exit 1
    declare -F locked_append >/dev/null || exit 1
    usage_json='"'"'{"input":1,"cache_creation":2,"cache_read":3,"processed":6,"output":4,"turns":5}'"'"'
    if compute_delta_line "$usage_json" fixture-session 2026-08-13T00:00:00Z false \
      0 0 0 0 0 '"'"'{"input":0,"cache_creation":0,"cache_read":0,"output":0,"turns":0}'"'"' \
      >/dev/null 2>&1; then
      exit 1
    fi
    if compute_legacy_line "$usage_json" fixture-session 2026-08-13T00:00:00Z false \
      >/dev/null 2>&1; then
      exit 1
    fi
  ' _ "$ROOT/scripts/lib/bureau-token-lib.sh" || exit 1
  echo PASS
expected: exit 0; stdout "PASS"; retired functions are undefined/calls fail and both surviving functions remain defined
