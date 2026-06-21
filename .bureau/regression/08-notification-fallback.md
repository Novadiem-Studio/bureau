name: Escalation writes a usable fallback file when the notifier fails
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  mkdir -p "$TMPDIR/checkpoints" "$TMPDIR/fakebin"
  # Force the notification-failure path WITHOUT breaking the rest of the
  # environment: shadow osascript with a fake that exits non-zero (first in PATH),
  # leaving date/mkdir/cat reachable so the fallback file is actually written with
  # content. (A blunt PATH="/nonexistent" also breaks date/mkdir/cat and would
  # leave a 0-byte fallback file that still passes a bare `test -f` — a false pass.)
  printf '#!/bin/sh\nexit 1\n' > "$TMPDIR/fakebin/osascript"
  chmod +x "$TMPDIR/fakebin/osascript"
  PATH="$TMPDIR/fakebin:$PATH" \
  "$ROOT/scripts/notify-escalation.sh" \
    "08" "$TMPDIR" "test escalation reason"; EXIT=$?
  echo "exit:$EXIT"
  test -f "$TMPDIR/checkpoints/ESCALATION-08.md" && echo "fallback:present" || echo "fallback:absent"
  grep -q 'test escalation reason' "$TMPDIR/checkpoints/ESCALATION-08.md" && echo "content:ok" || echo "content:MISSING"
expected: prints "exit:0", "fallback:present", and "content:ok" — osascript fails (incl. retry), so the notifier writes ESCALATION-08.md carrying the reason and exits 0 (never aborts the loop, EC4)
phase: 12 · principal-delegate
owner: scripts/notify-escalation.sh
