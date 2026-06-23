name: Bundle 14 P2 — verdict schema carries optional Integration-evidence (7 PascalCase keys), required still 7, root closed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '(.required|length==7) and (.additionalProperties==false) and (.properties["Integration-evidence"].type=="object") and (.properties["Integration-evidence"].additionalProperties==false) and (.properties["Integration-evidence"].properties | has("Gates-checked") and has("Pre-existing-validated") and has("Under-declaration") and has("Scope-diff-clean") and has("Scope-violations") and has("Fast-forward-ok") and has("Conflicts-clean"))' "$ROOT/config/delegate-verdict.schema.json"
expected: exit 0 — jq prints true; nonzero/false if Integration-evidence is missing, added to required, the root is opened, or any of the 7 keys drift
phase: 02 · execute-plan (Bundle 14)
owner: prompts.md Prompt 2 (config/delegate-verdict.schema.json)
