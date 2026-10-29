name: Verdict schema carries optional Integration-evidence with exactly seven PascalCase keys
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '
    (.required | index("Integration-evidence") == null)
    and (.additionalProperties == false)
    and (.properties["Integration-evidence"].type == "object")
    and (.properties["Integration-evidence"].additionalProperties == false)
    and (.properties["Integration-evidence"].properties | keys) ==
      (["Gates-checked", "Pre-existing-validated", "Under-declaration", "Scope-diff-clean",
        "Scope-violations", "Fast-forward-ok", "Conflicts-clean"] | sort)
  ' "$ROOT/config/delegate-verdict.schema.json"
expected: exit 0 — jq prints true; nonzero/false if Integration-evidence is missing, added to required, the root is opened, or any of the 7 keys drift
phase: 02 · execute-plan (Bundle 14)
owner: prompts.md Prompt 2 (config/delegate-verdict.schema.json)
