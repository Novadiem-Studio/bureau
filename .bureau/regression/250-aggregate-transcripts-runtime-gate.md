name: aggregate-transcripts exits at the runtime gate before transcript resolution
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); RUN_PATH="$TMPF/run"; mkdir -p "$RUN_PATH"
  printf '{"runtime":"openai"}\n' > "$RUN_PATH/model-routing.json"
  # No state, delegate-state, log, pointer, projects root, or transcript exists: any post-gate read leaks leg output/noise.
  stderr="$TMPF/stderr"
  out=$(BUREAU_CLAUDE_PROJECTS_DIR="$TMPF/does-not-exist" HOME="$TMPF/no-home" "$ROOT/scripts/aggregate-transcripts.sh" "$RUN_PATH" 2>"$stderr")
  rc=$?
  expected='{"_runtime_gap":"openai — no Claude JSONL; named Codex gap (docs/host-runtime.md)"}'
  [ "$out" = "$expected" ] && [ ! -s "$stderr" ]; ok=$?
  rm -rf "$TMPF"; [ "$rc" -eq 0 ] && [ "$ok" -eq 0 ] || exit 1; echo "PASS"
  # Mutation note: removing the early exit produces leg JSON and/or attempts absent transcript inputs, failing byte equality.
expected: exit 0; stdout "PASS"; gated stdout is exactly the single _runtime_gap object and stderr is empty
phase: 01 · execute-plan
owner: Prompt 01 / aggregate-transcripts.sh runtime gate seam
