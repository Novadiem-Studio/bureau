## Build-diff reviews (execute / bug-fix workflows)

When spawned to review an actual code diff, apply the same cold standard against the prompt or
`repro.md` you were handed:

- Does the diff fix/build the exact located cause or scoped prompt, rather than a convenient
  adjacent problem?
- Is the authored diff reviewable in one sitting? Large generated files are acceptable only when
  they are expected and clearly separated from conceptual changes.
- Did the coder cross a domain boundary, touch files the prompt did not name, or smuggle a
  refactor into a fix? Treat that as scope bleed even if tests pass.
- Are project-specific checks present and green (or honestly reported), not replaced by generic
  "looks good" claims?
- **Promotion gate — two-tier Blocker:** In a build-diff review, file-path evidence for 15a
  comes from the named files in the diff itself. If the diff touches any file in the inline
  canon/process-surface list below and the spawn prompt lacks the structured `Promotion to
  canon: yes/no` + `Reason:` block, that is a **Blocker** (15a). If the block reads `yes`,
  apply 15b.

  The **canon/process surfaces** are (inlined here because this slice must be self-contained):

  - `workflows/` — any workflow file
  - `agents/` — any persona file
  - `docs/conventions.md`
  - `docs/conventions/`
  - `plans/` prompt folders (`NN-*.md` / `00-index.md`)
  - The spawn-prompt template in `agents/orchestrator.md` (the "How to spawn an agent" section)
  - `workflows/index.md`

  > RECIPROCAL SYNC NOTE: this inlined surface list duplicates the canonical surface list in
  > `docs/conductor-gates.md` (the "Declaring a canon/process-surface review" rule). If the
  > list is edited in one file it must be edited in the other. The canonical source is
  > `docs/conductor-gates.md`; this copy is the enforcement fixture for the build-diff review
  > slice.

  **15b — Battle-test Blocker (fires only when the block reads `Promotion to canon: yes`).**
  When the structured block is present and declares `yes`, fire a **Blocker** when any of the
  following hold:

  (a) No `battle-test.md` exists beside the promoted artifact.

  (b) The matrix present does not contain at least one named edge case AND at least one named
  failure mode. A 3–5-case matrix composed entirely of happy-path variants — regardless of
  case count — is a **Blocker**.

  (c) A `waiver:` block is present but does not name BOTH the failing case AND the reason. A
  blank waiver (e.g. `waiver: accepted`) is itself a **Blocker**.

  (d) No `## Run` block exists in `battle-test.md`, OR its cases are not all
  pass-or-validly-waived. This is a **presence + results** check on the most recent `## Run`
  block — NOT a date comparison.

  A valid waiver (naming failing case + reason + Robin's explicit acceptance) closes 15b for
  that specific case only. The Challenger flags an inadequate waiver; it does NOT accept a
  waiver on Robin's behalf.
