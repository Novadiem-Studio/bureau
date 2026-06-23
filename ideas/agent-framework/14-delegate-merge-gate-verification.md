---
priority: bundle-14
status: idea
suggested-workflow: feature
suggested-run-slug: delegate-merge-gate-verification
source-ideas:
  - 09-principal-delegate.md (shipped; this extends it)
---

# 14. Delegate verification gate at integration boundaries

## Purpose

The shipped Delegate (Bundle 09) reasons off run-dir artifacts (state.json, log.md, the
build's own report), not a live session, because the design constraint was token burn. That
makes it a plausibility checker, not a verifier. At an integration boundary (merge to main,
deploy, fixture/prod promotion) trusting the build's self-report IS rubber-stamping. This
bundle adds a verification pass that independently re-executes the load-bearing claims before
the gate clears, and keeps it cheap by spending that effort only at the rare high-stakes gates.

## The gap (worked example: 2026-06-22 Track-3 merge)

The Track-3 build reported, accurately: 4 commits, ~85 tests green, standing suite 5/5,
typecheck + build clean, one pre-existing red (`private-routes` AC-PRIVATE) it claimed also
fails at base main. A reasons-off-files gate accepts that report as-is.

What actually closed the merge decision was re-execution against the repo, not reading the
report:
- Re-ran typecheck, the full integration suite (243/244), the standing regression (5/5), and
  the production build, in the worktree. Reproduced green, did not read "green."
- Scope-diffed `base...branch`: grepped the committed diff for edge/compaction symbols and got
  zero, confirming the design-checkpoint scope cut survived into the code.
- **Reproduced the one red at the merge base.** It failed identically at base main, proving it
  was pre-existing and not a Track-3 regression.

That last check is the difference between verification and rubber-stamping. A build that
introduced a regression can label it "pre-existing" (honestly mistaken or not), and only
re-running the failing test at the merge base catches the lie. A file-reasoning gate cannot do
this; it has no ground truth to compare against.

## The protocol (integration-gate verification checklist)

When a checkpoint is an integration boundary (merge / deploy / promote), the Delegate runs:

1. **Re-run the claimed gates** in the worktree (typecheck, test suite, standing regression,
   build). The verdict requires reproducing green, not reading it.
2. **Scope-diff** `base...branch` against the agreed/spec scope; assert no out-of-scope files or
   symbols. Catches scope creep past a design-checkpoint cut.
3. **Reproduce every "pre-existing / not my fault" red at the merge base.** Fails at base =
   genuinely pre-existing, non-blocking. Passes at base but fails on the branch = a regression
   the build mislabeled, so revise/escalate. This is the anti-rubber-stamp check.
4. **Confirm clean integration:** base unmoved / fast-forward, or no conflicts.
5. **Emit proceed / revise / escalate** with the evidence attached.

## Why this stays inside the Delegate's charter

Every step is mechanical verification of whether the build's claims are TRUE. Zero
preference-modeling, so it does not violate FR-44. The Delegate still never decides what Robin
wants; it decides whether the artifacts say what the build says they say. Proceed only if
everything verifies. Escalate to Robin only on a verification failure (a "pre-existing" red
that does not reproduce at base, a scope violation, gates that do not reproduce green) or a
genuine triage call it should merely SURFACE not decide (e.g. "the pre-existing red is a
privacy leak — Robin sets severity"; the Delegate flags the finding, does not set priority).

## Resolving the token tension that shaped Bundle 09

09 reasons off files to stay cheap. Re-execution is expensive. Resolve by tiering the gate to
checkpoint stakes:
- Keep cheap file-reasoning for routine in-flight / phase-boundary checkpoints.
- Spend the expensive re-execution pass ONLY at integration boundaries (merge / deploy /
  promote), which happen about once per run, so the cost is bounded.

The Conductor already re-runs the standing regression gate before each dispatch, so the
execution capability partly exists. This bundle wires an INDEPENDENT verifier into the merge
gate so the build cannot grade its own homework at the one checkpoint where being wrong reaches
main.

## Acceptance boundary

On a run that reaches a merge checkpoint, the Delegate (verifying mode) re-runs the claimed
gates, scope-diffs, reproduces any claimed-pre-existing red at the merge base, and emits a
verdict with evidence, with no human re-doing it. Regression fixture: the 2026-06-22 Track-3
merge replayed yields "proceed; 1 red, reproduced at base; scope clean; fast-forward."

## Relationship to other bundles

- **Extends Bundle 09 (Principal delegate, shipped).** Adds a verifying mode for high-stakes
  gates to a Delegate that today only reasons off files.
- **Complements Bundle 05 (external Notary cold review)** and **Bundle 01b (regression gates).**
- **Distinct from the Challenger,** which reviews code correctness per phase off the diff. This
  is integration-gate claim-verification by re-execution, a different job at a different moment.
