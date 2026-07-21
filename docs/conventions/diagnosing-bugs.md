# Diagnosing Bugs Discipline

> Canon module. Load this file for `bug-fix` workflow reproduce/fix work, especially when
> the cause is foggy or a regression test must be chosen.

## Purpose

Bug fixes need a red-capable feedback loop before they need a theory. The loop must exercise
the user's actual symptom, become sharper as the diagnosis proceeds, and end as a committed
regression test whenever a correct seam exists.

This sharpens the existing `bug-fix` workflow. It does not create a second diagnosis artifact:
`RUN_DIR/repro.md` remains the single home for the repro, located cause, probes, and
regression-test evidence.

## Tight Loop First

Before locating or fixing the cause, create a feedback loop that is:

- Red-capable: it drives the real bug path and can fail on the reported symptom.
- Deterministic: same verdict on repeated runs, or a documented high reproduction rate for a
  non-deterministic bug.
- Fast enough to guide debugging.
- Agent-runnable without live human judgment.

Good loops include failing tests, curl/HTTP scripts, CLI invocations with fixture inputs,
headless browser scripts, replayed traces, throwaway harnesses, property/fuzz loops,
bisection harnesses, and differential old/new-version checks.

If no red-capable loop can be built, stop and raise a checkpoint. Name what was tried and ask
for the missing access, captured artifact, or permission for temporary instrumentation.

## Minimise Before Theory

Once the loop goes red, minimise it. Remove inputs, callers, config, data, or steps one at a
time and rerun the loop. Keep only elements whose removal makes the bug disappear.

Do not minimise forever. Stop when the remaining elements are load-bearing enough that the
root-cause search is smaller and the eventual regression test has a plausible seam.

## Hypothesise And Instrument When Foggy

If reading the minimised path locates the cause, skip this section and fix.

If the cause is still foggy:

- Generate 3-5 ranked hypotheses before testing any one of them.
- Make every hypothesis falsifiable: name the prediction it makes.
- Add only targeted probes that distinguish hypotheses. Change one variable at a time.
- Prefer debugger or REPL inspection when available; otherwise use boundary logs or timing
  measurements.
- Tag temporary debug logs with one unique prefix such as `[DEBUG-a4f2]`.
- Remove all temporary instrumentation before handoff; grep the prefix to prove cleanup.

Never "log everything and grep." A broad logging spray is not diagnosis.

## Regression Test Home Rule

The fix should leave a committed test that fails on the pre-fix code and passes after the fix.
The home is target-repo specific:

- Bureau target: a committed `.bureau/regression/NNN-slug.md` fixture.
- App target: a test in the app's own existing suite, using the local `testing` skill,
  `CLAUDE.md`, or sub-app convention to choose the harness.

The test must exercise a correct seam: the real bug pattern as it occurs at the call site. A
too-shallow unit test that cannot reproduce the triggering chain is false confidence.

When no correct seam exists, do not fake a test. Write
`Regression test: none — no correct seam` in `RUN_DIR/repro.md`, including attempted seams, why
each is too shallow, and the follow-up needed to make the bug lockable. This is a testability
debt finding, not a clean success path.

## `repro.md` Contract

`RUN_DIR/repro.md` is the cold-review artifact. Keep it factual and handoff-safe:

- Bug symptom: the exact user-reported failure.
- Feedback loop: command/steps and red evidence.
- Minimized repro: remaining load-bearing inputs/steps.
- Located cause: file + symbol + why.
- Hypotheses/probes: only if cause was foggy.
- Regression seam: chosen test home and why it is the correct seam.
- Regression evidence: test path, pre-fix red command/output, post-fix green command/output;
  or the explicit no-correct-seam record.
- Debug cleanup: prefix grepped clean, or `none used`.

Do not put `log.md`, prior Challenger findings, or chat rationale in `repro.md`. The Challenger
reads it cold.
