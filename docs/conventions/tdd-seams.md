# TDD Seam Discipline

> Canon module. Load this file only when writing or executing build prompts that name
> `Seams under test:` in their checkpoint.

## Purpose

Test at the seam where behavior is observable, not at the private helper that happens to
exist today. A seam is a public interface the feature genuinely crosses: an endpoint, job,
service method, reducer transition, component behavior, CLI command, migration invariant, or
integration contract.

## Prompt Contract

Every build prompt's `## Checkpoint` starts with exactly one declaration:

```markdown
Seams under test: <named public seam(s) and behavior pinned>
```

or, when the prompt has no meaningful test seam:

```markdown
Seams under test: none — <short reason>
```

`none` is valid for migrations, mechanical wiring, generated sync, visual-only polish, and
other work where a test seam would be theater. The declaration is still required so the gap is
intentional and reviewable.

## Good Seams

- Exercise behavior through public interfaces: HTTP request/response, command output, reducer
  state transition, rendered user behavior, job side effect, or persisted data invariant.
- Cover one vertical slice at a time. Prefer one real entry point with a small fixture over
  many shallow assertions across unrelated layers.
- Pin the behavior that would hurt if it regressed, especially blockers or edge cases found
  during the run.

## Anti-Patterns

- Implementation-coupled tests: asserting private helper calls, internal instance variables,
  or temporary structure that can change while behavior stays correct.
- Tautological tests: repeating the implementation's condition in the assertion.
- Horizontal slicing: tests that only prove a model, route, or component exists without
  proving the cross-layer behavior the prompt is meant to ship.

## Mutation Verification

For every non-`none` seam, the coder verifies the test by briefly breaking or inverting the
guarded behavior in a throwaway edit, confirming the seam test fails, restoring the code, and
rerunning the checkpoint green. If a mutation cannot be applied safely, the coder states the
reason in the handoff and treats the seam as unverified.
