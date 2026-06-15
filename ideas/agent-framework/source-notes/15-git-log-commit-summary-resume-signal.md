---
priority: 15
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: git-log-commit-summary-resume-signal
---

# 15. Git-log / commit-message summary as resume signal

## One-liner
Use standardized commit messages as a first-class resume and context-priming signal alongside `state.json` and `log.md`, so a fresh session can orient quickly from the git log without reading every artifact.

## Problem
Resuming a run in a new session requires reading `state.json`, `log.md`, and often several artifact files. This works but is slow. The git log for the same work often tells a cleaner story — if commits are well-named. Currently, commits are not standardized in a way the framework can parse, so the git log is useful for humans but not for structured resume.

## Idea
1. Define a commit message convention for framework build runs: phase name, workflow step, result (accepted/failed/partial), and a one-line summary.
2. Add a step in `execute-plan` and `operational-build` workflows that commits (or at least stages) after each accepted phase with a conforming message.
3. Add `scripts/resume-from-git.sh` (or equivalent) that reads the last N commits on the current branch, extracts the framework-tagged ones, and emits a structured resume summary.
4. The Conductor can use this summary as the first-look context in a resumed session, supplemented by `state.json` for machine-readable fields.

## Likely home
Commit message convention in `docs/conventions.md` or a new `docs/commit-convention.md`. `scripts/resume-from-git.sh`. Phase acceptance step in `execute-plan` workflow. Conductor resume instructions in `agents/orchestrator.md`.

## Done when
After three accepted phases of a build run, running `scripts/resume-from-git.sh` produces a readable summary of what was built, what passed, and where the run stopped — in under 10 seconds, without reading `log.md`. The Conductor can use this as a cold-start context primer.

## Open questions
- Should framework commit messages use a prefix (`[bureau]`) or a structured trailer (`Bureau-Phase: 2/setup`)?
- How should the convention handle commits that touch both framework artifacts and project code in the same worktree?
- Should resume-from-git replace `state.json` priming, or supplement it?

## Non-goals
Replacing `state.json` as the authoritative run state. Parsing arbitrary commit messages not written by the framework. Rewriting existing project commit message conventions.
