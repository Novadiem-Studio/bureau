name: FR4 REPLACE ownership gate registers reviewer only, preserves reviewer marker parity, and catches a de-registered stub that emits
owner: check-framework.sh OWNERSHIP_EMITTERS count parity and arm-3 public verdict
phase: 06 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  REPO="$TMPF/repo"
  HOME_DIR="$TMPF/home"
  mkdir -p "$HOME_DIR/.claude"
  cp -R "$ROOT" "$REPO"
  jq -n --arg status "$REPO/scripts/statusline-usage.sh" \
    '{hooks:{},statusLine:{type:"command",command:$status}}' > "$HOME_DIR/.claude/settings.json"

  ownership_line=$(grep '^OWNERSHIP_EMITTERS=' "$REPO/check-framework.sh")
  [ "$ownership_line" = 'OWNERSHIP_EMITTERS=(scripts/append-reviewer-tokens.sh)' ] \
    || { echo "FAIL: ownership set is not reviewer-only"; exit 1; }
  for stub in scripts/conductor-stop.sh scripts/subagent-stop.sh; do
    if grep -vE '^[[:space:]]*#' "$REPO/$stub" \
      | grep -E 'locked_append' \
      | grep -qE 'TOKEN-EVENT|EVENT_PREFIX'; then
      echo "FAIL: retired stub still contains a token-event emit: $stub"
      exit 1
    fi
  done
  reviewer_emits=$(grep -vE '^[[:space:]]*#' "$REPO/scripts/append-reviewer-tokens.sh" \
    | grep -E 'locked_append' \
    | grep -cE 'TOKEN-EVENT|EVENT_PREFIX' || true)
  reviewer_markers=$(grep -cE '^[[:space:]]*# *OWNERSHIP-GATE:[[:space:]]*[^[:space:]]' \
    "$REPO/scripts/append-reviewer-tokens.sh" || true)
  [ "$reviewer_emits" -gt 0 ] && [ "$reviewer_markers" -ge "$reviewer_emits" ] \
    || { echo "FAIL: reviewer emit/marker baseline parity is not enforced"; exit 1; }

  HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$REPO/check-framework.sh" > "$TMPF/baseline.out" 2>&1 \
    || { echo "FAIL: reviewer-only ownership baseline did not yield framework exit 0"; exit 1; }

  cp "$REPO/scripts/append-reviewer-tokens.sh" "$TMPF/reviewer.sh"
  printf '\nlocked_append "$LOG_MD" "REVIEWER-TOKEN-EVENT: {}"\n' \
    >> "$REPO/scripts/append-reviewer-tokens.sh"
  if HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$REPO/check-framework.sh" > "$TMPF/parity.out" 2>&1; then
    echo "FAIL: unmatched reviewer emit did not make framework verdict non-zero"
    exit 1
  fi
  grep -Fq 'token-emit ownership: scripts/append-reviewer-tokens.sh has' "$TMPF/parity.out" \
    || { echo "FAIL: reviewer count-parity diagnostic missing"; exit 1; }
  cp "$TMPF/reviewer.sh" "$REPO/scripts/append-reviewer-tokens.sh"
  HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$REPO/check-framework.sh" > "$TMPF/parity-restored.out" 2>&1 \
    || { echo "FAIL: restoring reviewer emitter did not return framework to exit 0"; exit 1; }

  cp "$REPO/scripts/conductor-stop.sh" "$TMPF/conductor.sh"
  printf '\nlocked_append "$RUN_DIR/log.md" "CONDUCTOR-TOKEN-EVENT: {}"\n' \
    >> "$REPO/scripts/conductor-stop.sh"
  if HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$REPO/check-framework.sh" > "$TMPF/arm3.out" 2>&1; then
    echo "FAIL: de-registered stub emit did not make framework verdict non-zero"
    exit 1
  fi
  grep -Fq 'new token emitter scripts/conductor-stop.sh not in the ownership-coverage known set' "$TMPF/arm3.out" \
    || { echo "FAIL: arm-3 diagnostic missing for de-registered stub"; exit 1; }
  cp "$TMPF/conductor.sh" "$REPO/scripts/conductor-stop.sh"
  HOME="$HOME_DIR" PATH=/usr/bin:$PATH "$REPO/check-framework.sh" > "$TMPF/arm3-restored.out" 2>&1 \
    || { echo "FAIL: restoring de-registered stub did not return framework to exit 0"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; only append-reviewer-tokens.sh is registered, reviewer marker/count parity remains live, both retired stubs are de-registered and emission-free, parity and arm-3 mutations yield non-zero, and every restored throwaway copy reruns green
