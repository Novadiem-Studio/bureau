name: live-hook delta functions are retired while post-hoc summation and reviewer locking survive
owner: scripts/lib/bureau-token-lib.sh FR4 REPLACE surface
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  bash -c '
    source "$1"
    ! declare -F compute_delta_line >/dev/null
    ! declare -F compute_legacy_line >/dev/null
    declare -F sum_transcript_usage >/dev/null
    declare -F locked_append >/dev/null
    ! compute_delta_line 2>/dev/null
    ! compute_legacy_line 2>/dev/null
  ' _ "$ROOT/scripts/lib/bureau-token-lib.sh" || exit 1
  echo PASS
expected: exit 0; stdout "PASS"; retired functions are undefined/calls fail and both surviving functions remain defined
