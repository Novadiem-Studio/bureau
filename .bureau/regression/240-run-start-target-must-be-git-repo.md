name: run-start.sh — --target must be a git repo ROOT; a non-root subdir of a repo fails (no state.json), a real root passes, "(no-target)" is still allowed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  RS="$ROOT/scripts/run-start.sh"
  TMPF=$(mktemp -d)
  POINTER_DIR="$TMPF/active-runs"; mkdir -p "$POINTER_DIR"
  SLUG2="20260811-b5-subdir-$$"
  SLUGR="20260811-b5-root-$$"
  SLUGN="20260811-b5-notarget-$$"
  cleanup() {
    rm -rf "$TMPF"
    for s in "$SLUG2" "$SLUGR" "$SLUGN"; do
      rm -f "$ROOT/output/studio/runs-index/$s.json" "$ROOT/output/studio/runs-index/.$s.json.tmp"
    done
  }
  trap cleanup EXIT INT TERM

  # ── CASE 2 (the real viralvision hazard): a NON-repo-root dir that sits INSIDE a git
  # ancestor. `git -C <subdir> rev-parse --is-inside-work-tree` returns TRUE here, so the
  # naive fix would still (wrongly) accept it — the fixture MUST use this subdir case, not
  # a plain non-git dir, or it would pass against the insufficient is-inside-work-tree fix.
  # The correct rule (--show-toplevel == the target) rejects it: FAIL, no state.json.
  git -C "$TMPF" init -q
  MONO="$TMPF/viralvision"; mkdir -p "$MONO"
  RUN_DIR2="$MONO/.bureau/runs/$SLUG2"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$RS" "$RUN_DIR2" \
    --target "$MONO" --workflow feature --slug "$SLUG2" --no-pointer-echo >/dev/null 2>"$TMPF/e2"
  rc2=$?
  [ "$rc2" -ne 0 ] || { echo "FAIL: CASE 2 (subdir under git ancestor) was accepted (rc=0)"; exit 1; }
  [ ! -f "$RUN_DIR2/state.json" ] || { echo "FAIL: CASE 2 wrote a state.json"; exit 1; }
  PATH=/usr/bin:$PATH grep -qi "not a git repository ROOT" "$TMPF/e2" \
    || { echo "FAIL: CASE 2 message unclear: $(cat "$TMPF/e2")"; exit 1; }

  # ── REAL REPO ROOT: passes and records target_repo.
  REPO="$TMPF/realrepo"; mkdir -p "$REPO"; git -C "$REPO" init -q
  RUN_DIRR="$REPO/.bureau/runs/$SLUGR"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$RS" "$RUN_DIRR" \
    --target "$REPO" --workflow feature --slug "$SLUGR" --no-pointer-echo >/dev/null 2>"$TMPF/er"
  rcr=$?
  [ "$rcr" -eq 0 ] || { echo "FAIL: real repo root rejected (rc=$rcr): $(cat "$TMPF/er")"; exit 1; }
  [ -f "$RUN_DIRR/state.json" ] || { echo "FAIL: real repo root wrote no state.json"; exit 1; }

  # ── REAL REPO ROOT with a TRAILING SLASH: canonical compare must still accept it
  # (a trailing slash or symlinked path must not false-reject a real root).
  SLUGS="20260811-b5-slash-$$"
  RUN_DIRS="$REPO/.bureau/runs/$SLUGS"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$RS" "$RUN_DIRS" \
    --target "$REPO/" --workflow feature --slug "$SLUGS" --no-pointer-echo >/dev/null 2>"$TMPF/es"
  rcs=$?
  rm -f "$ROOT/output/studio/runs-index/$SLUGS.json" "$ROOT/output/studio/runs-index/.$SLUGS.json.tmp"
  [ "$rcs" -eq 0 ] || { echo "FAIL: real repo root with trailing slash rejected (rc=$rcs): $(cat "$TMPF/es")"; exit 1; }

  # ── "(no-target)" sentinel: the git check must NOT reject it (clean early bypass).
  # The no-target fallback routes target_repo through here as this exact string; a later
  # step may still exit non-zero (the sentinel is not a real dir), but our git check must
  # emit NO "not a git repository" rejection for it.
  RUN_DIRN="$TMPF/nt/.bureau/runs/$SLUGN"
  BUREAU_POINTER_DIR="$POINTER_DIR" bash "$RS" "$RUN_DIRN" \
    --target "(no-target)" --workflow feature --slug "$SLUGN" --no-pointer-echo >/dev/null 2>"$TMPF/en" || true
  if PATH=/usr/bin:$PATH grep -qi "not a git repository" "$TMPF/en"; then
    echo "FAIL: (no-target) sentinel was rejected by the git check: $(cat "$TMPF/en")"; exit 1
  fi

  echo "PASS"
  # Mutation note: drop the git-root guard in scripts/run-start.sh (the block that requires
  # `git rev-parse --show-toplevel` == the normalized --target, gated on TARGET != "(no-target)")
  # → CASE 2 is accepted (rc=0, state.json written) → this fixture goes RED. Using
  # `--is-inside-work-tree` INSTEAD of the toplevel-equality compare would ALSO regress
  # CASE 2 (true for a subdir), which is why the subdir case is load-bearing here.
expected: exit 0; stdout "PASS"; run-start rejects a non-repo-root subdir of a git repo with a clear "not a git repository ROOT" message and writes no state.json; accepts a real repo root (incl. trailing-slash form); and does not reject the literal "(no-target)" sentinel via the git check.
phase: bug-fix · framework-instrumentation-fixes
owner: Bug 5 / scripts/run-start.sh --target git-repo-root validation (toplevel-equality, (no-target) bypass)
