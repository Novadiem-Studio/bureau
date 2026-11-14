name: run-cold-reviewer.sh caps the Claude reviewer by turns (DELEGATE_MAX_TURNS, default 200), never by dollars, and names a turn-limit stop
owner: scripts/run-cold-reviewer.sh Claude reviewer spawn; agents/delegate.md turn-limit rule (issue #141)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RD="$TMPF/run"
  CTX="$RD/checkpoints/01-context"
  mkdir -p "$CTX/conventions"
  printf '# reviewer\n' > "$CTX/delegate-reviewer.md"
  cp "$ROOT/AGENTS.md" "$CTX/bureau-agents.md"
  printf '# conventions\n' > "$CTX/conventions.md"
  printf '# module\n' > "$CTX/conventions/agent-contracts.md"
  printf '# slice\n' > "$CTX/log-slice.md"
  printf '# artifact\n' > "$CTX/artifact.md"
  printf '{"target_repo":"%s","scope":{}}\n' "$TMPF/target" > "$CTX/state.json"
  cp "$CTX/state.json" "$RD/state.json"
  cp "$CTX/artifact.md" "$CTX/log-slice.md" "$RD/"
  python3 - "$RD" <<'PYRECIPE'
  import json, pathlib, sys
  r = pathlib.Path(sys.argv[1])
  (r / 'checkpoints/01-review-sources.json').write_text(json.dumps({'files': {
      n: [str(r / n)] for n in ('artifact.md', 'log-slice.md', 'state.json')}}))
  PYRECIPE
  : > "$RD/log.md"
  printf '{"runtime":"claude","roles":{"delegate":{"model":"opus"}}}\n' > "$RD/model-routing.json"
  # A stub claude that records its argv and stops the way the real CLI does at
  # the turn limit: exit 1 with subtype error_max_turns on stdout.
  mkdir -p "$TMPF/bin"
  cat > "$TMPF/bin/claude" <<STUB
  #!/bin/sh
  printf '%s\n' "\$@" > "$TMPF/argv"
  printf '{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":201}\n'
  exit 1
  STUB
  chmod +x "$TMPF/bin/claude"
  run() { # run <spawn-id> <env...>
    sid="$1"; shift
    env -u DELEGATE_MAX_TURNS "$@" PATH="$TMPF/bin:$PATH" BUREAU_REVIEWER_HOST=claude BUREAU_REVIEWER_MODEL=opus \
      bash "$ROOT/scripts/run-cold-reviewer.sh" "$RD" "$CTX" 01 "$sid" artifact.md routine >/dev/null 2>"$TMPF/err"
  }
  turns_arg() { awk 'p{print; exit} $0=="--max-turns"{p=1}' "$TMPF/argv"; }

  # Default: --max-turns 200, no dollar flag, and the failure names the turn limit.
  run 01-1 && { echo "FAIL: a turn-limit stop exited 0"; exit 1; }
  [ -f "$TMPF/argv" ] || { echo "FAIL: the stub claude was never reached"; cat "$TMPF/err"; exit 1; }
  [ "$(turns_arg)" = "200" ] || { echo "FAIL: default --max-turns is '$(turns_arg)', want 200"; exit 1; }
  grep -q -- '--max-budget-usd' "$TMPF/argv" && { echo "FAIL: reviewer still passes --max-budget-usd"; exit 1; }
  grep -q 'stopped at the turn limit' "$TMPF/err" || { echo "FAIL: turn-limit stop not named"; cat "$TMPF/err"; exit 1; }

  # Override: DELEGATE_MAX_TURNS reaches the CLI.
  rm -f "$TMPF/argv"
  run 01-2 DELEGATE_MAX_TURNS=350
  [ "$(turns_arg)" = "350" ] || { echo "FAIL: DELEGATE_MAX_TURNS=350 gave --max-turns '$(turns_arg)'"; exit 1; }

  # A turn-limit stop leaves no verdict behind.
  ls "$RD/checkpoints"/*-reviewer-verdict.json >/dev/null 2>&1 && { echo "FAIL: a turn-limit stop left a verdict"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". The Claude reviewer spawn passes `--max-turns 200` by default and `--max-turns 350` under DELEGATE_MAX_TURNS=350, never `--max-budget-usd`. When the CLI stops with subtype error_max_turns, run-cold-reviewer.sh fails with "stopped at the turn limit" and leaves no verdict. Mutation: put back `--max-budget-usd "$BUDGET"` in place of `--max-turns "$MAX_TURNS"` → the default-turns assertion fails; delete the error_max_turns branch → the "stopped at the turn limit" assertion fails; hardcode 200 → the override assertion fails.
phase: reviewer limits are turns, not dollars (issue #141)
