name: watcher routine checkpoint dispatches through the Codex adapter, writes a bound verdict, and appends one normalized reviewer token event
phase: multi-host Codex adapter
owner: scripts/watcher.sh + scripts/run-cold-reviewer.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RD="$TMPF/run"
  mkdir -p "$RD/checkpoints"
  printf '# artifact\n' > "$RD/artifact.md"
  printf '# slice\n' > "$RD/log-slice.md"
  HASH=$(shasum -a 256 "$RD/artifact.md" | awk '{print $1}')
  printf '{"target_repo":"%s/target","scope":{"allowed_paths":["**"],"cut_symbols":[]}}\n' "$TMPF" > "$RD/state.json"
  printf '{"runtime":"openai","roles":{"delegate":{"model":"gpt-5.6-sol","reasoningEffort":"high"}}}\n' > "$RD/model-routing.json"
  cat > "$RD/checkpoints/01-request.md" <<REQ
  checkpoint: 01
  run-dir: $RD
  artifact: $RD/artifact.md
  artifact-hash: $HASH
  log-slice: $RD/log-slice.md
  checkpoint-type: routine
  revise-count: 0
  attempt: 1
  REQ

  FAKE="$TMPF/fake-codex"
  export HASH
  cat > "$FAKE" <<'SH'
  #!/bin/sh
  out=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then shift; out="$1"; fi
    shift
  done
  printf '{"Decision":"proceed","Artifact-hash":"%s","Uncertainties":"none","Rationale":"fixture","Required-changes":"none","Escalation":"none","Ledger":"fixture"}\n' "$HASH" > "$out"
  printf '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":3,"cache_write_input_tokens":2,"output_tokens":4}}\n'
  SH
  chmod +x "$FAKE"

  CODEX_BIN="$FAKE" RUN_DIR="$RD" ROOT="$ROOT" sh "$ROOT/scripts/watcher.sh" "$RD" \
    >"$TMPF/watcher.out" 2>"$TMPF/watcher.err" &
  WPID=$!
  i=0
  while [ ! -s "$RD/checkpoints/01-verdict.md" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  kill "$WPID" 2>/dev/null
  wait "$WPID" 2>/dev/null

  grep -Eq '^decision:[[:space:]]+proceed$' "$RD/checkpoints/01-verdict.md" \
    || { cat "$TMPF/watcher.err"; echo "FAIL: bound verdict not written"; exit 1; }
  grep -q 'Cold reviewer prompt — spawn: 01-1-1, runtime: openai' "$RD/log.md" \
    || { echo "FAIL: pre-spawn prompt audit line missing"; exit 1; }
  grep 'Cold reviewer prompt' "$RD/log.md" | grep -Fq "$RD" \
    && { echo "FAIL: Codex prompt audit leaked the live RUN_DIR"; exit 1; }
  EVENT=$(grep '^REVIEWER-TOKEN-EVENT:' "$RD/log.md" | tail -1 | sed 's/^REVIEWER-TOKEN-EVENT: //')
  printf '%s' "$EVENT" | jq -e '
    .spawn_id == "01-1-1"
    and .turns == 1
    and .tokens.input == 7
    and .tokens.cache_creation == 2
    and .tokens.cache_read == 3
    and .tokens.processed == 12
    and .tokens.output == 4
  ' >/dev/null || { echo "FAIL: normalized reviewer token event"; printf '%s\n' "$EVENT"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; watcher uses the OpenAI runtime helper, audits a snapshot-only prompt before spawn, verdict-write accepts the artifact-bound verdict, and exactly one 01-1-1 reviewer event records normalized usage.
