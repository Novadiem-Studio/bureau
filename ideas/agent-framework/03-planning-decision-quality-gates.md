---
priority: bundle-03
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: planning-decision-quality-gates
source-ideas:
  - source-notes/10-analyst-value-metric.md
  - source-notes/12-assumption-reduction-question-pass.md
  - source-notes/02-approach-bakeoff.md
---

# 03. Planning decision quality gates

## Purpose

Improve the decisions made before build work starts: name the outcome the work should move,
make hidden assumptions explicit, and only run a bake-off when implementation uncertainty is
high enough to justify parallel exploration.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `10-analyst-value-metric` | Make the intended outcome observable before the spec is written. |
| `12-assumption-reduction-question-pass` | Convert hidden greenfield assumptions into decisions, deferrals, or checkpoints. |
| `02-approach-bakeoff` | Add an optional workflow for genuinely uncertain implementation strategy. |

## Why this is one bundle

All three ideas answer the same question: "Are we building from a decision, a guess, or an
unexamined preference?" They should be one planning discipline, not three separate ceremonies.

## First implementation slice

1. Add a required Analyst field:
   `Outcome / bottleneck: <what this work must improve, how it will be observed, or why this run is explicitly exploratory>`.
2. Add a Challenger check that rejects non-observable metrics only when the run is not
   explicitly exploratory.
3. Add a greenfield-only assumption section to the Analyst-to-Architect handoff:
   - assumption;
   - decision/answer;
   - deferred with reason;
   - needs Visionary checkpoint.
4. Add a small "bake-off trigger" rule to `agents/architect.md`:
   recommend a bake-off only when two or more viable approaches have materially different
   cost, reversibility, risk, or fit with existing code.

Do not create the full bake-off workflow until the trigger has appeared in at least one real
run. A trigger rule is cheaper and proves demand.

## Later implementation slice

When the trigger proves useful, create `workflows/approach-bakeoff.md`:

- maximum three tracks;
- criteria declared before any track starts;
- isolated worktrees or artifact folders;
- same test/review criteria for each track;
- explicit discard step for losers;
- no external side effects;
- winner canonized only after Challenger review.

## Done when

- Every non-exploratory feature spec names an observable bottleneck or outcome.
- Greenfield specs distinguish decisions from assumptions.
- The Architect has a documented threshold for proposing a bake-off.
- Bake-offs are optional, bounded, and criteria-first.

## Risks

- Metrics can become theater if they are trivially satisfied or impossible to observe.
- Assumption reduction can slow down small features if applied outside greenfield/high-risk work.
- Bake-offs can multiply work if the trigger is too loose. Use them for expensive uncertainty,
  not ordinary implementation choice.

