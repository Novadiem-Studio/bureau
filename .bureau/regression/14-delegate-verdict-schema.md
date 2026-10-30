name: Delegate verdict schema requires artifact coverage, is closed, and has the fixed Decision enum
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '
    (.required | sort) == (["Decision", "Artifact-hash", "Artifacts-read", "Uncertainties",
      "Rationale", "Required-changes", "Escalation", "Ledger"] | sort)
    and (.additionalProperties == false)
    and (.properties.Decision.enum == ["proceed", "revise", "escalate"])
    and (.properties["Artifacts-read"].type == "array")
    and (.properties["Artifacts-read"].minItems == 1)
    and (.properties["Artifacts-read"].items.required | sort) == ["path", "sha256"]
    and (.properties["Artifacts-read"].items.additionalProperties == false)
  ' "$ROOT/config/delegate-verdict.schema.json"
expected: exit 0 — jq prints true; removing required artifact coverage, changing required fields, opening either object, or changing the Decision enum fails.
phase: 02 · execute-plan
owner: prompts.md Prompt 2 (config/delegate-verdict.schema.json)
