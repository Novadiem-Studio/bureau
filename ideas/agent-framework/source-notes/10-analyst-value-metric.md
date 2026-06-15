---
priority: 10
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: analyst-value-metric
---

# 10. Analyst value metric

## One-liner
Before the spec is written, name the specific bottleneck or outcome the work is meant to improve — so the framework can test whether the finished build actually moved it.

## Problem
Builds get shipped that do not move anything measurable. The work was real, the code is correct, but there was no predeclared outcome to test against. This produces theater builds: they pass acceptance criteria written at the same time as the code, and nobody can say whether they improved the thing that mattered.

## Idea
1. Add a mandatory field to the Analyst's output: "What is the bottleneck or outcome this work is meant to improve, and how will we know it improved?"
2. The metric should be specific and observer-independent: not "improve performance" but "reduce p95 build time below 30s" or "cut analyst revision round-trips from 3 to 1."
3. The Challenger reviews the metric before the spec is finalized — a metric that cannot be observed or is trivially satisfied does not pass.
4. At close-out, add a step that checks the metric: did it move? If not measurable yet (needs production data), record a plan for when and how it will be checked.
5. Over time, feed metric outcomes into the studio accounting ledger alongside cost and model mix.

## Likely home
Analyst output template in `agents/analyst.md` + Challenger checklist item + close-out step in any build workflow. Optionally fed into the per-run accounting ledger (idea 05).

## Done when
Every Analyst handoff includes a named metric. The Challenger can reject a metric as non-observable. The close-out step records whether the metric was verified, deferred, or waived with a reason.

## Non-goals
Making every run about metrics — some runs are exploratory or structural. The metric step should be skippable for explicitly exploratory work, with a recorded reason.
