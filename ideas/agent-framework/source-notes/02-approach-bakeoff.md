---
priority: 02
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: approach-bakeoff
---

# 02. Approach bake-off workflow

## One-liner
When implementation strategy is genuinely uncertain, run two or three independent approaches in isolation, evaluate each against predeclared criteria, pick a winner, and discard the losers cleanly.

## Problem
For uncertain implementation decisions, the framework currently picks one path and iterates. Sometimes two or three isolated attempts would converge on the right solution faster than one path that keeps pivoting. There is no structured way to do this — it collapses into ad hoc back-and-forth.

## Idea
1. Define the question, constraints, and evaluation criteria before any building starts.
2. Spawn two or three independent approaches in separate worktrees or prompt tracks.
3. Test or review each candidate against the same predeclared criteria (same Challenger lens, same test inputs).
4. Conductor chooses one winner, explicitly discards the losers, and canonizes only the winning pattern.

## Guardrails
- Maximum three tracks — never more.
- No production or external side effects during a bake-off.
- No merging partial losers into the winner.
- Evaluation criteria must be declared before spawning the first track. If criteria are missing, abort and define them first.

## Likely home
New `approach-bakeoff` workflow, or an optional branch inside the `feature` or `execute-plan` workflow when The Architect flags high implementation uncertainty.

## Done when
A workflow exists with: an explicit criteria-declaration step, per-track isolated artifacts, Challenger review of each candidate, and a Conductor decision log naming the winner and why the others were rejected.

## Open questions
- Should this be a standalone workflow or a branch inside an existing one?
- At what uncertainty threshold should The Architect recommend a bake-off vs. iterating?
