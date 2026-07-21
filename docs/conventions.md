# Agent-Framework Block Conventions

This file is now the convention router. Do not pre-load every convention module on every
spawn. Read this small router when a persona says `Convention: docs/conventions.md`, then load
only the module whose trigger matches the work.

## Convention read scope (token discipline)

**Always-read core:**
1. `docs/conventions.md` (this file).

**Load on demand:**
- `docs/conventions/agent-contracts.md` — editing or auditing persona `## Inputs` blocks,
  handoff footers, acceptance criteria, `Passing forward` / `carried_items`, exempt-role
  handling, or the file ↔ role alias table.
- `docs/conventions/workflow-authoring.md` — authoring or reviewing workflows, runbooks,
  workflow registry hints, workflow parser step lines, or cast-name/tier/output arrows.
- `docs/conventions/regression-fixtures.md` — creating, rerunning, promoting, retiring, or
  validating regression fixture files.
- `docs/conventions/grilling.md` — initial Analyst pass in the `feature` workflow, pre-spec
  grill checkpoints, and user-fact provenance in Requirements.
- `docs/conventions/tdd-seams.md` — writing or executing build prompts whose checkpoint
  declares `Seams under test:`; use it to choose public seams and mutation-verify seam tests.
- `docs/conventions/fowler-smell-baseline.md` — build-diff Standards-axis reviews; use it
  as the fixed smell floor when target-repo docs are silent or incomplete.
- `docs/conventions/canon-promotion.md` — canon promotion, `battle-test.md` matrices,
  waivers, or convention retirement/supersession.
- `docs/conventions/failure-signatures.md` — recording failure signatures, checking recurrence,
  or closing the lessons-append gate.

If a module is not triggered, do not read it "just in case." The old broad
`Convention: docs/conventions.md` pointer means: load this router first, then only the matching
module.

## Pointer rule

Every persona file that gains an `## Inputs` block still carries a one-line
`Convention: docs/conventions.md` pointer. The pointer targets this router, not the whole
convention corpus.
