name: Cold reviewer resume claim stays exclusive when mkdir is not — Rust coreutils mkdir (Ubuntu 26.04) can report success to two racers, so the claim record is written under noclobber and exactly one of two concurrent replays publishes the audit line (issue #131)
phase: ubuntu-26.04 runner (issue #131)
owner: scripts/run-cold-reviewer.sh cursor branch; scripts/watcher.sh lock_dir; scripts/usage-snapshot-hook.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RD="$TMPF/run"
  CTX="$RD/checkpoints/01-context"
  CP="$RD/checkpoints"
  mkdir -p "$CTX/conventions"
  printf '# reviewer\n' > "$CTX/delegate-reviewer.md"
  cp "$ROOT/AGENTS.md" "$CTX/bureau-agents.md"
  printf '# conventions\n' > "$CTX/conventions.md"
  printf '# module\n' > "$CTX/conventions/agent-contracts.md"
  printf '# slice\n' > "$CTX/log-slice.md"
  printf '# artifact\n' > "$CTX/artifact.md"
  HASH=$(shasum -a 256 "$CTX/artifact.md" | awk '{print $1}')
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
  cat > "$RD/model-routing.json" <<JSON
  {"runtime":"cursor","roles":{"delegate":{"model":"gpt-5.6-sol-medium"}},"hostPolicy":{"allowed_spawn_models":["composer-2.5-fast","gpt-5.6-sol-medium","cursor-grok-4.6-high-fast","claude-opus-5-thinking-high"]}}
  JSON
  # A mkdir that never refuses: the behaviour measured on GitHub's ubuntu-26.04 runner
  # (uutils coreutils 0.10.0 mkdir, both of two racers exit 0 in 10 of 300 rounds),
  # made deterministic. It also pauses inside mkdir for the claim path, so two racers
  # that enter it milliseconds apart both leave it together and both reach the record
  # write while neither has finished: the collision is forced, not hoped for. Every
  # script run below sees it first on PATH.
  REAL_MKDIR=$(command -v mkdir)
  mkdir -p "$TMPF/shim"
  printf '#!/bin/sh\ncase "$*" in *reviewer-task-plan.claim) sleep 0.5 ;; esac\nexec "%s" -p "$@"\n' "$REAL_MKDIR" > "$TMPF/shim/mkdir"
  chmod +x "$TMPF/shim/mkdir"
  d="$TMPF/shim-check"; PATH="$TMPF/shim:$PATH" mkdir "$d" && PATH="$TMPF/shim:$PATH" mkdir "$d" || { echo "FAIL: shim mkdir still refuses an existing dir"; exit 1; }
  run() { PATH="$TMPF/shim:$PATH" bash "$ROOT/scripts/run-cold-reviewer.sh" "$@"; }
  cat > "$TMPF/resp.json" <<JSON
  {"result":{"Decision":"revise","Artifact-hash":"$HASH","Artifacts-read":[{"path":"artifact.md","sha256":"$HASH"}],"Uncertainties":"none","Rationale":"fixture","Required-changes":"architecture: tighten the lease","Escalation":"none","Ledger":"fixture","Integration-evidence":null},"usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20},"num_turns":3}
  JSON

  # two concurrent first resumes of one plan: exactly one audit line, one verdict
  set +e
  run "$RD" "$CTX" 01 01-2-1 artifact.md routine >/dev/null 2>&1
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-2-1 artifact.md routine >/dev/null 2>"$TMPF/a1.err" & A1=$!
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-2-1 artifact.md routine >/dev/null 2>"$TMPF/a2.err" & A2=$!
  wait "$A1"; R1=$?
  wait "$A2"; R2=$?
  set -e
  [ $((R1 + R2)) -le 1 ] || { echo "FAIL: concurrent resumes under permissive mkdir: rc $R1 and $R2"; cat "$TMPF/a1.err" "$TMPF/a2.err"; exit 1; }
  n=$(grep -c 'Cold reviewer resume — spawn: 01-2-1,' "$RD/log.md")
  [ "$n" = "1" ] || { echo "FAIL: concurrent resumes under permissive mkdir wrote the audit line $n times"; cat "$TMPF/a1.err" "$TMPF/a2.err"; exit 1; }
  [ "$(jq -r .status "$CP/01-2-1-reviewer-task-plan.json")" = "resumed" ] || { echo "FAIL: plan not marked resumed"; exit 1; }
  [ ! -e "$CP/01-2-1-reviewer-task-plan.claim" ] || { echo "FAIL: claim left behind"; exit 1; }

  # two concurrent same-response replays (raw published, plan reset): the 26.04 failure shape
  jq '.status = "host-task-required" | del(.resumedAt, .responseFile, .responseSha256)' "$CP/01-2-1-reviewer-task-plan.json" > "$TMPF/p" && mv "$TMPF/p" "$CP/01-2-1-reviewer-task-plan.json"
  grep -v 'Cold reviewer resume — spawn: 01-2-1,' "$RD/log.md" > "$TMPF/log" && mv "$TMPF/log" "$RD/log.md"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-2-1 artifact.md routine >/dev/null 2>"$TMPF/b1.err" & B1=$!
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-2-1 artifact.md routine >/dev/null 2>"$TMPF/b2.err" & B2=$!
  wait "$B1"; S1=$?
  wait "$B2"; S2=$?
  set -e
  [ $((S1 + S2)) -le 1 ] || { echo "FAIL: concurrent replays under permissive mkdir: rc $S1 and $S2"; cat "$TMPF/b1.err" "$TMPF/b2.err"; exit 1; }
  n=$(grep -c 'Cold reviewer resume — spawn: 01-2-1,' "$RD/log.md")
  [ "$n" = "1" ] || { echo "FAIL: concurrent replays under permissive mkdir wrote the audit line $n times"; cat "$TMPF/b1.err" "$TMPF/b2.err"; exit 1; }
  [ "$(jq -r .status "$CP/01-2-1-reviewer-task-plan.json")" = "resumed" ] || { echo "FAIL: replay did not mark the plan"; exit 1; }
  [ ! -e "$CP/01-2-1-reviewer-task-plan.claim" ] || { echo "FAIL: replays left a claim"; exit 1; }

  # the loser of the record write never removes the winner's claim: a claim dir with a
  # live record stays refused and intact
  set +e
  run "$RD" "$CTX" 01 01-2-2 artifact.md routine >/dev/null 2>&1
  set -e
  mkdir "$CP/01-2-2-reviewer-task-plan.claim"
  printf '{"pid":"%s","at":"2026-09-15T00:00:00Z"}\n' "$$" > "$CP/01-2-2-reviewer-task-plan.claim/claim.json"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-2-2 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'already claimed' "$TMPF/err" || { echo "FAIL: live claim not refused under permissive mkdir"; cat "$TMPF/err"; exit 1; }
  [ -f "$CP/01-2-2-reviewer-task-plan.claim/claim.json" ] || { echo "FAIL: loser removed the live claim"; exit 1; }
  [ ! -e "$CP/01-2-2-reviewer-verdict.json" ] || { echo "FAIL: refused resume published"; exit 1; }

  # the static guards on the other two lock sites: noclobber record writes present in real code
  strip() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
  strip "$ROOT/scripts/watcher.sh" | grep -Fq 'set -C; echo "$$" > "$lock_dir/pid"' || { echo "FAIL: watcher.sh lock_dir pid write is not under noclobber"; exit 1; }
  strip "$ROOT/scripts/usage-snapshot-hook.sh" | grep -Fq 'set -C; echo "$$" > "$LOCK/owner"' || { echo "FAIL: usage-snapshot-hook.sh lock owner write is not under noclobber"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". With a mkdir that never refuses an existing directory and pauses inside the claim mkdir so both racers reach the record write together (the uutils coreutils race on Ubuntu 26.04 made deterministic), two concurrent first resumes of one plan and two concurrent same-response replays each append the audit line of record exactly once, mark the plan resumed, and leave no claim; a resume that meets a claim dir holding a live record is refused and leaves that record intact; watcher.sh and usage-snapshot-hook.sh write their lock records under `set -C` in real (non-comment) code. Mutation: drop the `set -C` around the claim.json write in run-cold-reviewer.sh → both racers claim and the audit line is written twice (the exact ubuntu-26.04 failure of fixture 296); make the record-write failure fall through instead of `fail` → the same; drop the noclobber from watcher.sh or usage-snapshot-hook.sh → the static guard fails.
