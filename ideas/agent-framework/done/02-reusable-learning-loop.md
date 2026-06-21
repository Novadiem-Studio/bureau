---
priority: bundle-02
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: reusable-learning-loop
source-ideas:
  - source-notes/01-self-annealing-failure-loop.md
  - source-notes/03-doc-sync-pass.md
  - source-notes/09-close-out-reusable-learning-pass.md
---

# 02. Reusable learning loop

## Purpose

Make failures and repeated corrections improve the reusable framework layer before the run
ends. The core behavior is: capture the failure, patch the right durable artifact, verify the
smallest representative case, and keep docs synchronized with executable ground truth.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `01-self-annealing-failure-loop` | The immediate failure-to-fix loop. |
| `03-doc-sync-pass` | Keep runbooks and directive docs aligned after scripts or executable steps change. |
| `09-close-out-reusable-learning-pass` | Escalate repeated lessons into conventions, runbooks, scripts, or checks. |

## Dependency

Run this after Bundle 01's two slices if possible. The learning loop is much stronger when
failures have preflight artifacts, regression fixtures, and representative cases to point at.
`output/studio/` is the existing Studio Record used by The Witness; this bundle owns the
lessons surface inside it (`output/studio/lessons.md` and any README section), not the whole
directory.

## Memory integration boundary

Rheo persistent memory is an active sibling track, not the implementation of this bundle.
It currently runs in the remote MOT/Rheo runtime while the Bureau framework runs locally.
Memory may surface candidate lessons or recurring procedural patterns, but it does not promote
canon and the local framework must not assume direct write access to the remote memory store.
Promotion still happens through the framework learning loop: Conductor adjudication,
Challenger-checkable evidence, and a durable local artifact such as `docs/conventions.md`, a
runbook, or `output/studio/lessons.md`.

## First implementation slice

Do not create a new persona first. Add a close-out discipline and one repair path:

1. Add a "Failure repair" subsection to `workflows/operational-build.md` and
   `workflows/execute-plan.md`.
2. Define a failure signature format in `docs/conventions.md`:
   - failing command/tool/runbook step;
   - observed error;
   - suspected layer: script, workflow directive, env/preflight, external contract, target code;
   - durable artifact patched;
   - smallest verification case.
3. Add a `docs-sync-needed` close-out check for any changed script, runbook, or workflow.
   This must be Challenger-checkable, not just a flag the Conductor can wave past: the
   required form is "for every script/runbook/workflow changed this run, name the durable
   artifact patched — or state explicitly why none." A flag with no required body is theater.
4. Create or update the lessons surface in the Studio Record:
   `output/studio/README.md` if missing or missing a lessons section, plus
   `output/studio/lessons.md` as the human-readable learning log.
5. Add a minimal recurrence rule: a lesson seen in two runs must be either promoted or
   explicitly deferred with a reason.
6. Add a one-paragraph **convention-retirement rule** to `docs/conventions.md`: to deprecate
   a convention, mark it superseded (name the replacement), set a removal date, and add a
   Challenger check that a superseded block is not still cited as a live instruction. This
   bundle roughly doubles the convention surface in `conventions.md` and the persona files;
   without a retirement path the document becomes unreadable and cold reviewers encounter
   contradictory instructions.

Scripts can come later. The v1 win is making the Conductor stop treating repeated fixes as
session-local knowledge.

## Likely follow-up

After the convention has appeared in real runs:

- add `scripts/scan-lessons.sh` to find recurring failure signatures;
- create a `runbook-repair` workflow if repairs become common enough;
- add a docs-reconcile variant that runs specifically after script/runbook changes;
- add a Challenger checklist for "fix is in the reusable layer, not only in log.md."

## Done when

- A failed operational/build run records a failure signature and the durable artifact patched.
- The fix is verified against the smallest representative case.
- `output/studio/README.md` and `output/studio/lessons.md` exist.
- If a script or runbook changed, matching docs are reconciled before close-out or a carried
  item explains why not.
- A repeated lesson across two runs is promoted, deferred, or intentionally scoped local.

## Risks

- "Self-annealing" can become overcorrection if transient failures are treated as structural.
- Doc-sync can become a second full review workflow; keep it least-privilege and grounded in
  executable truth.
- Lesson matching can become fuzzy. Start with manual tags and exact failure signatures before
  adding clever inference.
