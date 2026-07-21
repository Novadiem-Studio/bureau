## Build-diff reviews (execute / bug-fix workflows)

When spawned to review an actual code diff, apply the same cold standard against the prompt or
`repro.md` you were handed:

Use two axes and keep them separate:

### Spec-fidelity axis

Question: did the diff build/fix the exact scoped prompt or located cause?

Check for:
- Missing, partial, or incorrectly implemented prompt/repro requirements.
- Scope creep: behavior, files, features, or refactors the prompt did not ask for.
- Wrong sequence or contract drift against earlier accepted build parts.
- Checkpoints that are absent, substituted with generic checks, or reported green without
  proving the behavior the prompt named.
- **Bug-fix regression-test gate:** When reviewing a `bug-fix` diff, load
  `docs/conventions/diagnosing-bugs.md` and check `RUN_DIR/repro.md` plus the diff. A missing
  committed regression test is a **Blocker** unless `repro.md` explicitly says
  `Regression test: none — no correct seam` and explains attempted seams, why each is too
  shallow, and the follow-up needed to make the bug lockable. A regression test that lacks
  pre-fix red evidence OR post-fix green evidence in `repro.md` is a **Blocker**. If the test
  appears not to exercise the real bug pattern at the call site, flag it; mutation-verify when
  the evidence is ambiguous. A valid no-correct-seam finding is at least a Standards warning
  because the codebase cannot lock the bug down.

### Standards axis

Question: does the diff meet the target repo's engineering standards?

Load `docs/conventions/fowler-smell-baseline.md`. Review against target repo docs and local
CLAUDE.md/skills first; where they are silent, apply the Fowler smell baseline as a floor.
Baseline smells are labelled heuristics (`possible Feature Envy`), not hard violations by
themselves, and a documented repo standard overrides the baseline. Skip smells already enforced
by tooling unless the diff bypasses or weakens that tooling.

Check for:
- Reviewability: can the authored diff be understood in one sitting? Large generated files are
  acceptable only when expected and clearly separated from conceptual changes.
- Domain and file-scope boundaries: no crossed coder domain, prompt-unnamed files, or smuggled
  refactor.
- Project-specific checks present and green (or honestly reported), not replaced by generic
  "looks good" claims.
- Fowler-floor smells that create real maintenance risk in the changed hunks.

### Reporting contract

Write the build-diff review under these headings, in this order:

```markdown
### Spec-fidelity
#### Blockers
#### Warnings

### Standards
#### Blockers
#### Warnings

### Solid

### Axis summary
Spec-fidelity: <count blockers/warnings; worst issue or "clean">
Standards: <count blockers/warnings; worst issue or "clean">
```

Severity lives inside each axis: a Spec-fidelity warning is not ranked above a Standards
blocker, and a clean Standards axis cannot soften a Spec-fidelity blocker. Do not declare a
single cross-axis winner or overall "most important" issue; the Conductor adjudicates after
seeing both axes.

The JSON verdict record stays on the existing `agents/critic.md § Verdict record` schema. Do
not add axis fields to `RUN_DIR/verdicts/<attempt_id>.json` unless `scripts/verdict-gate.sh`
and its fixtures are updated in the same change. Axis membership is a review-output contract,
not a record-schema field today.
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
Write `RUN_DIR/verdicts/<attempt_id>.json` per `agents/critic.md § Verdict record` (`review_mode: build-diff`; diff-target: bind the reviewed change via the pinned `git -C R diff <base_sha> [<target_sha>] | shasum -a 256 | awk '{print $1}'` invocation).
