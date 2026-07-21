name: run-start Delegate v2 startup — bare pointer written but nonce not echoed into Delegate transcript
phase: 06 · delegate-default-entrypoint
owner: scripts/run-start.sh --no-pointer-echo
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  bash "$ROOT/scripts/run-start.sh" --help | PATH=/usr/bin:$PATH grep -q -- "--no-pointer-echo" \
    || { echo "FAIL: run-start --help omits --no-pointer-echo"; exit 1; }
  TMPF=$(mktemp -d)
  SLUG="20260721-delegate-no-pointer-echo-fixture-$$"
  TARGET="$TMPF/target"
  RUN_DIR="$TARGET/.bureau/runs/$SLUG"
  POINTER_DIR="$TMPF/active-runs"
  mkdir -p "$TARGET" "$POINTER_DIR"
  git -C "$TARGET" init -q
  cleanup() {
    rm -rf "$TMPF"
    rm -f "$ROOT/output/studio/runs-index/$SLUG.json" "$ROOT/output/studio/runs-index/.$SLUG.json.tmp"
  }
  trap cleanup EXIT INT TERM

  out=$(BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/run-start.sh" \
    "$RUN_DIR" --target "$TARGET" --workflow feature --slug "$SLUG" --no-pointer-echo 2>"$TMPF/stderr")
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: run-start exited $rc"; cat "$TMPF/stderr"; exit 1; }

  KEY=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')
  POINTER_FILE="$POINTER_DIR/$KEY"
  [ -f "$POINTER_FILE" ] || { echo "FAIL: bare pointer was not written"; exit 1; }
  nonce=$(jq -r '.nonce // ""' "$POINTER_FILE" 2>/dev/null)
  [ -n "$nonce" ] || { echo "FAIL: pointer nonce absent"; exit 1; }

  # The Delegate top session must not receive the bare pointer nonce. It will
  # enroll and echo its own role:delegate pointer; the Conductor subagent reads
  # this bare pointer privately before spawning specialists.
  [ -z "$out" ] || { echo "FAIL: stdout was not suppressed: $out"; exit 1; }
  printf '%s' "$out" | PATH=/usr/bin:$PATH grep -qF "$nonce" \
    && { echo "FAIL: bare pointer nonce appeared on stdout"; exit 1; }
  PATH=/usr/bin:$PATH grep -qF "$nonce" "$RUN_DIR/log.md" \
    && { echo "FAIL: bare pointer nonce appeared in log.md"; exit 1; }
  PATH=/usr/bin:$PATH grep -q "Delegate v2 suppressed bare nonce echo" "$RUN_DIR/log.md" \
    || { echo "FAIL: v2 suppressed-echo enrollment line missing"; exit 1; }

  # The normal pre-spawn gate must still pass: the bare pointer exists and
  # model-routing.json was created, even though stdout did not carry the nonce.
  gate=$(BUREAU_POINTER_DIR="$POINTER_DIR" bash "$ROOT/scripts/spawn-gate.sh" "$RUN_DIR")
  [ "$gate" = "gate: clean" ] || { echo "FAIL: spawn-gate output: $gate"; exit 1; }

  echo "PASS"
  # Mutation notes:
  # (a) Delete the --no-pointer-echo branch and always cat the pointer: stdout is
  #     non-empty / contains the nonce, and this fixture fails.
  # (b) Skip the bare pointer write in v2 mode: spawn-gate fails because the
  #     specialist ownership nonce source is absent.
expected: exit 0; stdout "PASS"; run-start --no-pointer-echo writes the normal bare pointer, emits no stdout nonce, keeps the nonce out of log.md, records the v2 suppressed-echo line, and spawn-gate still passes
