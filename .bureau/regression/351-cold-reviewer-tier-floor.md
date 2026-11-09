name: run-cold-reviewer.sh refuses a sub-strong reviewer model (override or Delegate fallback) before spawning, on Claude and on a routing tiers map
owner: scripts/run-cold-reviewer.sh reviewer-model floor; config/model-policy.v2.json roles.challenger
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
  # A stub claude on PATH: if anything gets past the floor on the Claude host it
  # fails fast here instead of spawning a real reviewer.
  mkdir -p "$TMPF/bin"
  printf '#!/bin/sh\necho "stub claude: reached spawn" >&2\nexit 9\n' > "$TMPF/bin/claude"
  chmod +x "$TMPF/bin/claude"
  FLOOR='below the strong tier'
  n=0
  try() { # try <label> <expect: refused|passed> <env...>
    label="$1"; want="$2"; shift 2; n=$((n+1))
    env "$@" PATH="$TMPF/bin:$PATH" bash "$ROOT/scripts/run-cold-reviewer.sh" "$RD" "$CTX" 01 "01-1-$n" artifact.md routine >/dev/null 2>"$TMPF/err"
    if grep -q "$FLOOR" "$TMPF/err"; then got=refused; else got=passed; fi
    [ "$got" = "$want" ] || { echo "FAIL: $label — expected $want, got $got"; cat "$TMPF/err"; exit 1; }
  }

  # ── Claude host, no tiers map: haiku/sonnet are the sub-strong set ─────────
  printf '{"runtime":"claude","roles":{"delegate":{"model":"opus"}}}\n' > "$RD/model-routing.json"
  try "claude: sonnet override" refused BUREAU_REVIEWER_HOST=claude BUREAU_REVIEWER_MODEL=sonnet
  try "claude: haiku override" refused BUREAU_REVIEWER_HOST=claude BUREAU_REVIEWER_MODEL=haiku
  try "claude: opus override" passed BUREAU_REVIEWER_HOST=claude BUREAU_REVIEWER_MODEL=opus
  printf '{"runtime":"claude","roles":{"delegate":{"model":"sonnet"}}}\n' > "$RD/model-routing.json"
  try "claude: sonnet inherited from a downgraded Delegate" refused BUREAU_REVIEWER_HOST=claude

  # ── Cursor host with a tiers map: only cheap/standard-only models refused ──
  cat > "$RD/model-routing.json" <<'JSON'
  {"runtime":"cursor","roles":{"delegate":{"model":"gpt-5.6-sol-medium"}},"hostPolicy":{"allowed_spawn_models":["composer-2.5-fast","gpt-5.6-sol-medium","cursor-grok-4.6-high-fast"]},"tiers":{"cheap":{"model":"composer-2.5-fast"},"standard":{"model":"composer-2.5-fast"},"strong":{"model":"gpt-5.6-sol-medium"},"frontier":{"model":"cursor-grok-4.6-high-fast"},"escalated":{"model":"cursor-grok-4.6-high-fast"}}}
  JSON
  try "cursor: standard-tier model" refused BUREAU_REVIEWER_HOST=cursor BUREAU_REVIEWER_MODEL=composer-2.5-fast
  try "cursor: strong-tier model" passed BUREAU_REVIEWER_HOST=cursor BUREAU_REVIEWER_MODEL=gpt-5.6-sol-medium
  # A routing tiers map replaces the haiku/sonnet default: sonnet is not in this map.
  try "cursor: sonnet not named by the tiers map" passed BUREAU_REVIEWER_HOST=cursor BUREAU_REVIEWER_MODEL=gpt-5.6-sol-medium

  # Refusals leave no verdict behind.
  ls "$RD/checkpoints"/*-reviewer-verdict.json >/dev/null 2>&1 && { echo "FAIL: a refused review left a verdict"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". On the Claude host with no tiers map, BUREAU_REVIEWER_MODEL=sonnet or haiku, and a sonnet roles.delegate.model inherited as the fallback, are refused with "below the strong tier" before any spawn; opus passes the floor (and reaches the stub). On a routing with a tiers map, a model serving only cheap/standard (composer-2.5-fast) is refused and the strong-tier model plans normally. No refused call leaves a verdict. Mutation: delete the reviewer-model floor block in scripts/run-cold-reviewer.sh → the sonnet override passes and the first assertion fails; drop the strong-tier subtraction → unchanged here, covered by fixture 350; drop the Claude haiku/sonnet default → the Claude cases pass and fail.
phase: model policy — the cold reviewer never runs below strong (issue #133)
