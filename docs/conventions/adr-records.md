# ADR Records Discipline

> Canon module. Load this file when a run reads, writes, audits, or reconciles target-repo
> `docs/adr/` records.

## Purpose

ADR records are durable homes for load-bearing design decisions in the target repo. They are
project memory, not run history. Reading accepted ADRs does not weaken a cold review: the
Challenger is still cold to the current run's rationale, prior findings, and `log.md`; it is
only reading committed target-repo ground truth.

## Three Homes

- `CLAUDE.md` holds how to work in the repo: commands, conventions, and local process rules.
- `docs/adr/` holds why the repo is shaped this way: accepted architecture/product decisions.
- `CONTEXT.md` holds what words mean in the domain. The glossary ships later; do not create a
  shadow glossary in ADRs.

Keep each fact in one home. If a rule belongs in `CLAUDE.md`, do not duplicate it as an ADR. If
an ADR explains a design call, cite it instead of restating the full rationale elsewhere.

## What Qualifies

Create an ADR only when all three are true:

1. The decision is hard to reverse.
2. The decision would be surprising without context.
3. The decision resolved a real tradeoff.

Skip ADRs for obvious calls, reversible implementation details, TODOs, run notes, checklists,
or how-to instructions.

## Placement And Numbering

ADR records live in the target repo:

```text
<target-repo>/docs/adr/0001-short-slug.md
```

Create `docs/adr/` lazily. Number the next ADR by scanning existing
`docs/adr/[0-9][0-9][0-9][0-9]-*.md` files and incrementing the highest number. Use lowercase
ASCII slugs.

## Required Shape

```markdown
# ADR-0001: Short Title
Status: accepted
Date: YYYY-MM-DD

## Context
Why this decision exists, including the real tradeoff.

## Decision
The accepted decision.

## Consequences
Optional follow-on effects, risks, or costs.
```

Required fields:

- Filename number and heading number match.
- `Status:` is exactly `accepted` or `superseded-by-NNNN`.
- `Date:` is `YYYY-MM-DD`.
- `## Context` exists.
- `## Decision` exists.

When a decision changes, create a new ADR and update only the old ADR's `Status:` line to
`superseded-by-NNNN`. Do not rewrite the old body to make history look cleaner.

## Persona Rules

- Analyst: in existing-project mode, read accepted target-repo ADRs when `docs/adr/` exists
  and treat them as durable project facts. Do not write ADRs.
- Architect: in existing-project mode, read accepted target-repo ADRs before designing. Cite
  relevant existing ADRs, write new ADRs only for qualifying decisions, and supersede old ADRs
  when the new design intentionally replaces one.
- Challenger: in spec-plan review, read accepted target-repo ADRs when present. Flag any
  spec/plan contradiction with an accepted ADR unless the artifacts include a new
  superseding ADR.
- docs-reconcile: include `docs/adr/` status headers and accepted decisions in the drift
  survey. Reconcile drift by creating a superseding ADR, not by retconning old ADR bodies.
