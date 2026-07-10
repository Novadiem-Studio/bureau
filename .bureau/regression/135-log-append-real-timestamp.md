name: log-append.sh stamps a REAL shell-computed UTC time (never a fabricated placeholder), echoes it, is monotonic, and never clobbers log.md
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SC="$ROOT/scripts/log-append.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  RUN="$TMP/run"; mkdir -p "$RUN"

  # Pre-existing log.md content — the append must never clobber it.
  printf 'PRE-EXISTING LINE — must survive\n' > "$RUN/log.md"

  ISO='^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'

  # ── Call 1: heading only. Capture echoed stamp; assert it is the harness's own now. ──
  NOW1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  TS1=$(sh "$SC" "$RUN" "Spawned The Architect -> complete")

  # (a) echoed stamp matches the ISO-8601 UTC pattern
  echo "$TS1" | grep -Eq "$ISO" || { echo "FAIL: echoed TS1 [$TS1] not ISO-8601 UTC"; exit 1; }

  # (b) NOT a round-hour / midnight placeholder like the fabricated 00:00:00 drift
  case "$TS1" in *T00:00:00Z) echo "FAIL: TS1 is 00:00:00Z placeholder, not a real clock read"; exit 1;; esac

  # (c) REAL current time: within a few seconds of the harness's own date -u.
  # Compare as epoch seconds; a hardcoded/fabricated stamp is not close to now.
  e_now=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$NOW1" +%s 2>/dev/null || date -u -d "$NOW1" +%s)
  e_ts1=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$TS1"  +%s 2>/dev/null || date -u -d "$TS1"  +%s)
  d=$((e_ts1 - e_now)); [ "$d" -lt 0 ] && d=$((-d))
  [ "$d" -le 5 ] || { echo "FAIL: TS1 [$TS1] is ${d}s from now [$NOW1] — not a real-clock read"; exit 1; }

  # (d) the heading actually landed in log.md with that exact stamp
  grep -Fq "## [$TS1] — Spawned The Architect -> complete" "$RUN/log.md" \
    || { echo "FAIL: heading with echoed TS1 not found in log.md"; exit 1; }

  # ── Call 2: a second call must produce a NON-DECREASING (monotonic) stamp. ──
  TS2=$(sh "$SC" "$RUN" "The Challenger round 1 -> 2 blockers")
  echo "$TS2" | grep -Eq "$ISO" || { echo "FAIL: echoed TS2 [$TS2] not ISO-8601 UTC"; exit 1; }
  e_ts2=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$TS2" +%s 2>/dev/null || date -u -d "$TS2" +%s)
  [ "$e_ts2" -ge "$e_ts1" ] || { echo "FAIL: TS2 [$TS2] < TS1 [$TS1] — not monotonic"; exit 1; }

  # ── Body via stdin is appended verbatim under the heading. ──
  printf 'Handoff: verbatim body line\n' | sh "$SC" "$RUN" "Spawned Analizer 2000 -> complete" >/dev/null
  grep -Fq 'Handoff: verbatim body line' "$RUN/log.md" \
    || { echo "FAIL: piped body not appended verbatim"; exit 1; }

  # ── No clobber: the pre-existing line and both prior headings all still present. ──
  grep -Fq 'PRE-EXISTING LINE — must survive' "$RUN/log.md" \
    || { echo "FAIL: append clobbered pre-existing log.md content"; exit 1; }
  grep -Fq "## [$TS1] —" "$RUN/log.md" && grep -Fq "## [$TS2] —" "$RUN/log.md" \
    || { echo "FAIL: an earlier heading was lost across appends"; exit 1; }

  # ── --now primitive prints a real stamp and writes nothing new. ──
  BEFORE=$(wc -l < "$RUN/log.md")
  TSNOW=$(sh "$SC" --now)
  echo "$TSNOW" | grep -Eq "$ISO" || { echo "FAIL: --now [$TSNOW] not ISO-8601 UTC"; exit 1; }
  AFTER=$(wc -l < "$RUN/log.md")
  [ "$BEFORE" = "$AFTER" ] || { echo "FAIL: --now wrote to log.md (before=$BEFORE after=$AFTER)"; exit 1; }

  echo "PASS ts1=$TS1 ts2=$TS2 now=$TSNOW"
expected: |
  exit 0; stdout ends with a "PASS ts1=... ts2=... now=..." line.
  Every stamp matches ^20NN-NN-NNTNN:NN:NNZ, is within 5s of the harness's own date -u
  (so a real clock read, never a 00:00:00Z placeholder), is echoed to stdout, two successive
  calls are non-decreasing (monotonic), a piped body lands verbatim, and the pre-existing
  log.md line plus both prior headings survive every append. `--now` prints a stamp and
  writes nothing.
  MUTATION: replace the script's `TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"` with a hardcoded
  literal (e.g. TS="2026-01-01T00:00:00Z") and assertions (b)+(c) fail — the stamp is no
  longer close to now and hits the 00:00:00Z placeholder guard. Drop the `>>` append to `>`
  and the no-clobber assertion fails.
phase: 135 · framework-hardening (20260710-real-log-timestamps)
owner: scripts/log-append.sh — retire only if the mechanical-timestamp helper is removed
