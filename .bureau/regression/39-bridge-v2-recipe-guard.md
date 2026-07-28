name: delegate-bridge v2 canonical recipe uses the provider-neutral cold-reviewer helper and documents both host isolation guarantees
phase: 02 · execute-plan
owner: prompts.md § Prompt 2 (Phase 1)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DOC="$ROOT/docs/delegate-bridge/v2-integrated.md"
  grep -Fq 'scripts/run-cold-reviewer.sh' "$DOC" \
    && grep -Fq '**Claude adapter:**' "$DOC" \
    && grep -Fq '**Codex adapter:**' "$DOC" \
    && grep -Fq -- '--setting-sources ""' "$DOC" \
    && grep -Fq -- '--ignore-user-config' "$DOC" \
    && grep -Fq -- '--output-schema' "$DOC" \
    && echo "v2-recipe-guard-ok"
expected: prints "v2-recipe-guard-ok" — v2 uses one helper and documents both the preserved Claude isolation flags and the Codex ephemeral/schema isolation boundary.
