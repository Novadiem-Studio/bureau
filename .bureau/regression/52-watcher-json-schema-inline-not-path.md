name: cold-reviewer helper passes provider-correct schema forms and builds prompts only from the selected isolated context path
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  W="$ROOT/scripts/run-cold-reviewer.sh"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  strip "$W" | grep -Fq -- '--json-schema "$(cat "$SCHEMA")"' \
    || { echo "FAIL: Claude adapter does not inline the schema"; exit 1; }
  strip "$W" | grep -Fq -- '--output-schema "$CODEX_SCHEMA"' \
    || { echo "FAIL: Codex adapter does not pass the schema file"; exit 1; }
  strip "$W" | grep -Fq -- '${prompt_ctx}/delegate-reviewer.md' \
    || { echo "FAIL: prompt is not rooted in the selected isolated context"; exit 1; }
  ! strip "$W" | grep -Fq -- '${RUN_DIR}/delegate-reviewer.md' \
    || { echo "FAIL: prompt names a live RUN_DIR path"; exit 1; }
  echo PASS
expected: exit 0 — Claude gets inline schema contents, Codex gets an output-schema file, and the task prompt is rooted only in the provider-selected isolated context.
phase: multi-host Codex adapter
owner: scripts/run-cold-reviewer.sh
