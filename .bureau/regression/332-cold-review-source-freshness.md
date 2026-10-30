name: Cold review packets rebuild live sources and retain isolated per-spawn evidence (issue 98)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  python3 "$ROOT/scripts/check-cold-review-staging.py"
expected: exit 0; all freshness, archive, isolation and resume checks pass.
phase: reviewer staging
owner: scripts/stage-cold-review.py
