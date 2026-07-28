name: Codex verdict schema is strict at every object boundary and keeps routine Integration-evidence nullable
phase: multi-host Codex adapter
owner: config/delegate-verdict.codex.schema.json + scripts/run-cold-reviewer.sh
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/config/delegate-verdict.codex.schema.json"
  H="$ROOT/scripts/run-cold-reviewer.sh"
  jq -e '
    .additionalProperties == false
    and (.required | index("Integration-evidence")) != null
    and (.properties["Integration-evidence"].type | index("object")) != null
    and (.properties["Integration-evidence"].type | index("null")) != null
    and .properties["Integration-evidence"].additionalProperties == false
    and (.properties["Integration-evidence"].required | length) == 7
    and .properties["Integration-evidence"].properties["Gates-checked"].items.additionalProperties == false
    and .properties["Integration-evidence"].properties["Pre-existing-validated"].items.additionalProperties == false
    and .properties["Integration-evidence"].properties["Under-declaration"].items.additionalProperties == false
  ' "$S" >/dev/null || { echo "FAIL: Codex verdict schema is not strict"; exit 1; }
  grep -Fq -- '--output-schema "$CODEX_SCHEMA"' "$H" \
    && grep -Fq 'set Integration-evidence to null' "$H" \
    || { echo "FAIL: helper does not use/null-route the Codex schema"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; OpenAI structured-output constraints are satisfied without changing Claude's optional/open nested-evidence schema.
