name: log-append.sh stamps a REAL shell-computed UTC time (never fabricated), echoes it, is monotonic, never clobbers log.md, and the heading-only path never blocks on stdin
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

  # ── Body via stdin, OPT-IN with explicit trailing "-", is appended verbatim. ──
  printf 'Handoff: verbatim body line\n' | sh "$SC" "$RUN" "Spawned Analizer 2000 -> complete" - >/dev/null
  grep -Fq 'Handoff: verbatim body line' "$RUN/log.md" \
    || { echo "FAIL: opt-in (-) body not appended verbatim"; exit 1; }

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

  # ── NO-HANG: a heading-only call must NOT wait on stdin, even when stdin is an
  # open stream that never sends EOF. Portable (no `timeout` on macOS): hold a FIFO
  # open with a background writer that never EOFs, run the heading-only call in the
  # background with that FIFO as its stdin, sleep a short bound, then assert the call
  # has ALREADY exited. If it is still alive after the bound, it blocked on stdin.
  # fd hygiene: every background process's stdout/stderr is redirected to files or
  # /dev/null so none of them inherit (and hold open) this fixture's own stdout — else
  # the outer command substitution that runs the fixture would itself block on them.
  # cleanup() reaps the holder AND any `cat` child the call spawned (mutated script),
  # so a genuine hang is bounded here, not left to the harness timeout.
  FIFO="$TMP/fifo"; mkfifo "$FIFO"
  ( sleep 10 > "$FIFO" ) >/dev/null 2>&1 &
  HOLDER=$!
  sh "$SC" "$RUN" "no-hang heading only" < "$FIFO" > "$TMP/nohang.out" 2>/dev/null &
  CALL=$!
  cleanup_nohang() {
    # kill the call, any children it spawned (a surviving `cat`), and the FIFO holder.
    pkill -P "$CALL" 2>/dev/null || true
    kill "$CALL" "$HOLDER" 2>/dev/null || true
    wait "$CALL" "$HOLDER" 2>/dev/null || true
  }
  sleep 2
  if kill -0 "$CALL" 2>/dev/null; then
    cleanup_nohang
    echo "FAIL: heading-only call still running after 2s — it BLOCKED on a never-EOF stdin"; exit 1
  fi
  wait "$CALL"; rc_nohang=$?
  kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null || true
  [ "$rc_nohang" -eq 0 ] || { echo "FAIL: no-hang heading-only call exited non-zero ($rc_nohang)"; exit 1; }
  TSNH=$(cat "$TMP/nohang.out")
  echo "$TSNH" | grep -Eq "$ISO" || { echo "FAIL: no-hang call echoed non-ISO stamp [$TSNH]"; exit 1; }
  grep -Fq "## [$TSNH] — no-hang heading only" "$RUN/log.md" \
    || { echo "FAIL: no-hang heading not written to log.md"; exit 1; }

  echo "PASS ts1=$TS1 ts2=$TS2 now=$TSNOW nohang=$TSNH"
expected: |
  exit 0; stdout ends with a "PASS ts1=... ts2=... now=... nohang=..." line.
  Every stamp matches ^20NN-NN-NNTNN:NN:NNZ, is within 5s of the harness's own date -u
  (so a real clock read, never a 00:00:00Z placeholder), is echoed to stdout, two successive
  calls are non-decreasing (monotonic), an opt-in ("-") body lands verbatim, and the
  pre-existing log.md line plus both prior headings survive every append. `--now` prints a
  stamp and writes nothing. NO-HANG: a heading-only call with an open never-EOF FIFO on
  stdin returns within the 2s bound (it never reads stdin) and still writes its heading.
  MUTATION A (fabricated time): replace `TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"` with a
  hardcoded literal (e.g. TS="2026-01-01T00:00:00Z") → assertions (b)+(c) fail. Drop the
  `>>` append to `>` and the no-clobber assertion fails.
  MUTATION B (stdin blind spot): revert the body read to the tty inference
  `if [ ! -t 0 ]; then cat; fi` (dropping the explicit "-" opt-in) → the NO-HANG block's
  heading-only call now `cat`s the never-EOF FIFO and is still alive after 2s → FAIL.
phase: 135 · framework-hardening (20260710-real-log-timestamps)
owner: scripts/log-append.sh — retire only if the mechanical-timestamp helper is removed
