---
priority: 12
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: assumption-reduction-question-pass
---

# 12. Assumption-reduction question pass

## One-liner
Before a greenfield `spec.md` is finalized, run a structured pass that surfaces unstated assumptions and closes them with explicit answers — so the spec reflects decisions, not guesses.

## Problem
Greenfield specs contain hidden assumptions — about data ownership, scale, user behavior, integration surface, or available infrastructure — that the Analyst and Architect made implicitly. These surface as rework during or after implementation. The spec looks complete but is carrying unresolved questions as invisible load.

## Idea
1. After the Analyst produces a draft spec and before The Architect finalizes it, run an assumption-reduction pass.
2. The pass reviews the draft spec and generates a list of unstated assumptions: things treated as decided that have not been explicitly chosen.
3. For each assumption: either close it with an explicit answer (recorded in the spec), defer it with a recorded rationale, or escalate it to Robin if it is a Visionary-level decision.
4. The Challenger checks that the finalized spec does not contain bare assumptions — every major architectural or behavioral choice is either a decision or a recorded open question.

## Likely home
Step between Analyst and Architect handoff in the `feature` workflow. Could be a Challenger checklist item or a brief sub-pass in `agents/analyst.md`.

## Done when
A greenfield spec that previously contained implicit assumptions now has each assumption either answered explicitly or listed as a named open question. The Challenger can verify the spec is assumption-clean before Architect signs off.

## Open questions
- Should this be a standalone agent pass, a Challenger checklist item, or an Analyst self-review step?
- How should the pass distinguish genuine open questions (need Robin) from assumptions that can be closed by the Architect?
