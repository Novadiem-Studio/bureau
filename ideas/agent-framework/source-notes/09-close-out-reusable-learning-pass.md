---
priority: 09
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: close-out-reusable-learning-pass
---

# 09. Close-out reusable-learning pass

## One-liner
When the same lesson appears in two separate runs — same fix applied, same Challenger finding raised — promote it to a convention, test, or runbook so it does not have to be rediscovered a third time.

## Problem
Lessons learned in one run get recorded in `log.md` and then forgotten. The next run hits the same wall, reaches the same diagnosis, and applies the same fix. There is no mechanism that notices recurrence and escalates a lesson from "noted" to "canonical."

## Idea
1. At the close of each run, add a learning-scan step: review `log.md` for fixes applied, Challenger findings accepted, and corrections made.
2. Cross-reference against a studio-level learning log (`output/studio/lessons.md` or similar).
3. If a lesson appears in the current run that also appeared in a prior run (same pattern, different context), flag it as a recurring pattern.
4. Escalate recurring patterns to one of: a new convention in the relevant agent prompt or doc, a runbook entry, a Challenger checklist item, or a `check-framework.sh` warning.
5. Record the escalation decision — promoted, deferred (with reason), or intentionally left as a local note.

## Likely home
Close-out step in any workflow that produces a `log.md`. Studio learning log at `output/studio/`. Cross-referencing logic could live in a small script (`scripts/scan-lessons.sh`) or be part of the Conductor's close-out pass.

## Done when
After two runs that hit the same recurring pattern, the framework has promoted the fix to a durable artifact (convention, runbook entry, or Challenger checklist item). The studio learning log records when the escalation happened and what form it took.

## Open questions
- How does the framework detect "same lesson" across runs? Keyword matching? Structured fields in `log.md`? Manual tagging by the Conductor?
- Should the learning log live in the framework repo or alongside the run output in `output/studio/`?
- At what recurrence threshold should promotion happen — two identical occurrences, or two across different task types?
