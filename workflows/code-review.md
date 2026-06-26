# Workflow: code-review

**When to use:** the user asks for a review of an existing diff, branch, pull request, or
uncommitted changes before it goes to human review or merge. This is for "what is risky or
wrong in this code?" rather than "please build the fix."

**When NOT to use:** a known bug that needs reproduction and repair (use `bug-fix`); a plan that
needs decomposition and build (use `execute-plan`); prose/copy review (use `copy-review`); a raw
feature idea (use `feature`). If the user asks to both review and fix, run `code-review` first,
then route confirmed defects to `bug-fix` or the appropriate execution workflow.

**Type:** mixed (prepares a review target, runs a cold review, optionally runs project tests if
the user asked for a verification pass. It does not edit code by default.)

**Inputs:** target repo/path; base branch or PR URL if supplied; the diff/branch/uncommitted
changes to review; local project context (`CLAUDE.md` / `AGENTS.md` / relevant skills).

**Outputs:** under `RUN_DIR` (see `docs/run-protocol.md`): `review-target.md`, `review.md`,
`log.md`, `state.json`.

**Leans on skills:** **novadiem-engineering** plus the target sub-app's local context and testing
skill/runbook. Review against project standards, not a generic prompt.

## Steps

Run these as spawned subagents where named (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Pass `RUN_DIR` as an absolute path in every spawn prompt.

1. **The Conductor** (**strong**) — prepare the review target → `review-target.md`
   - Resolve the target: PR URL, branch/base, staged/uncommitted diff, or explicit file list.
   - Capture exact commands used to view the diff (`git diff <base>...HEAD`, `gh pr diff`, etc.),
     changed-file summary, local context files/skills to apply, and test commands if known.
   - Separate authored changes from expected generated/lockfile/schema churn when visible.
   - If the target is ambiguous, raise `[CHECKPOINT]`.
2. **The Challenger** (Critic, **strong**, fresh context required) — cold-review the target diff
   against `review-target.md` and local project standards → `review.md`, findings
   - It does NOT receive the author's rationale, chat history, or prior defense of the change.
   - It prioritizes bugs, regressions, data/security risks, scope bleed, missing tests, and
     unreviewable diff shape.
   - It reports findings in severity order with file/line references where possible.
3. **The Conductor** (**strong**) — adjudicate and summarize
   - Findings that would build or merge the wrong thing are blockers.
   - Warnings may be noted for the human reviewer or routed to a fix workflow if requested.
   - AI review does not replace human review; it narrows what the human should inspect.
4. **The Conductor** (**strong**) — optional verification, only if the user asked for it or the
   repo's review runbook requires it
   - Run the named test/lint commands from `review-target.md`.
   - Record pass/fail in `log.md` and include failures in the final review summary.

## Review target format

`review-target.md`:

```markdown
# Code Review Target

Target: <PR URL | branch | uncommitted changes | file list>
Repo: <absolute path>
Base: <branch/sha, or "not provided">
Diff command: `<exact command>`
Changed files: <short list or stat>
Generated/lockfile/schema churn expected: <yes/no + files>
Local standards: <CLAUDE.md / AGENTS.md / skills to load>
Tests/checks: <commands, or "none known">
Reviewer focus: <anything the user specifically asked to inspect, or "general correctness">
```

## Output format

`review.md`:

```markdown
# Code Review

## Findings

1. [P0/P1/P2/P3] <title> — <file:line>
   <why this matters and what should change>

## Open Questions

- <question, or "none">

## Tests / Verification

- <command>: <pass/fail/not run>

## Residual Risk

<anything the AI review could not verify>
```

Final response follows normal code-review style: findings first, then open questions, then a
short summary. If no issues are found, say that clearly and name any tests not run.
