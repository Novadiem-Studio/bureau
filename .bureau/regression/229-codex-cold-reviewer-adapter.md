name: Codex cold-reviewer adapter uses an isolated snapshot, normalizes stable JSONL usage, and returns deterministic metadata
phase: multi-host Codex adapter
owner: scripts/run-cold-reviewer.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RD="$TMPF/run"
  CTX="$RD/checkpoints/01-context"
  mkdir -p "$CTX/conventions"
  printf '# reviewer\n' > "$CTX/delegate-reviewer.md"
  printf '# conventions\n' > "$CTX/conventions.md"
  printf '# module\n' > "$CTX/conventions/agent-contracts.md"
  printf '# slice\n' > "$CTX/log-slice.md"
  printf '# artifact\n' > "$CTX/artifact.md"
  HASH=$(shasum -a 256 "$CTX/artifact.md" | awk '{print $1}')
  printf '{"target_repo":"%s","scope":{}}\n' "$TMPF/target" > "$CTX/state.json"
  cp "$CTX/state.json" "$RD/state.json"
  cat > "$RD/model-routing.json" <<JSON
  {"runtime":"openai","roles":{"delegate":{"model":"gpt-5.6-sol","reasoningEffort":"high"}}}
  JSON

  FAKE="$TMPF/fake-codex"
  FAKE_ARGS="$TMPF/args"
  export FAKE_ARGS HASH
  cat > "$FAKE" <<'SH'
  #!/bin/sh
  : > "$FAKE_ARGS"
  out=""
  while [ "$#" -gt 0 ]; do
    printf '%s\n' "$1" >> "$FAKE_ARGS"
    if [ "$1" = "-o" ]; then
      shift
      out="$1"
      printf '%s\n' "$1" >> "$FAKE_ARGS"
    fi
    shift
  done
  printf '{"Decision":"proceed","Artifact-hash":"%s","Uncertainties":"none","Rationale":"fixture","Required-changes":"none","Escalation":"none","Ledger":"fixture"}\n' "$HASH" > "$out"
  printf '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20,"reasoning_output_tokens":7}}\n'
  SH
  chmod +x "$FAKE"

  META=$(CODEX_BIN="$FAKE" bash "$ROOT/scripts/run-cold-reviewer.sh" \
    "$RD" "$CTX" 01 01-1-1 artifact.md routine)
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: adapter exited $rc"; exit 1; }
  VP=$(printf '%s' "$META" | jq -r .verdict_path)
  EP=$(printf '%s' "$META" | jq -r .envelope_path)
  [ "$(printf '%s' "$META" | jq -r .runtime)" = "openai" ] \
    || { echo "FAIL: metadata runtime"; exit 1; }
  jq -e --arg hash "$HASH" '.Decision == "proceed" and ."Artifact-hash" == $hash' "$VP" >/dev/null \
    || { echo "FAIL: normalized verdict"; exit 1; }
  jq -e '
    .num_turns == 1
    and .usage.input_tokens == 60
    and .usage.cache_read_input_tokens == 40
    and .usage.cache_creation_input_tokens == 5
    and .usage.output_tokens == 20
  ' "$EP" >/dev/null || { echo "FAIL: normalized usage envelope"; cat "$EP"; exit 1; }
  grep -Fq -- '--ephemeral' "$FAKE_ARGS" \
    && grep -Fq -- '--ignore-user-config' "$FAKE_ARGS" \
    && grep -Fq -- '--ignore-rules' "$FAKE_ARGS" \
    && grep -Fq -- 'default_permissions="bureau-review"' "$FAKE_ARGS" \
    && grep -Fq -- '--output-schema' "$FAKE_ARGS" \
    || { echo "FAIL: required Codex isolation arguments missing"; exit 1; }
  PROMPT=$(tail -1 "$FAKE_ARGS")
  printf '%s' "$PROMPT" | grep -Fq "$RD" \
    && { echo "FAIL: prompt leaked live RUN_DIR"; exit 1; }
  printf '%s' "$PROMPT" | grep -Fq '/staged/artifact.md' \
    || { echo "FAIL: prompt did not use snapshot path"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; the fake Codex transport receives the ephemeral/no-config permission-profile recipe, its prompt names only the copied snapshot, and 100 total input with 40 cached normalizes to input=60/cache_read=40.
