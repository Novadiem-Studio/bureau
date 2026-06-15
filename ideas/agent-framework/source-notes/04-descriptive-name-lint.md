---
priority: 04
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: descriptive-name-lint
---

# 04. Descriptive-name lint

## One-liner
A warning-only check that flags vague or misleading script, workflow, and runbook names so fresh agents can navigate the framework without relying on context that only exists in a human's head.

## Problem
Generic names make agentic navigation worse. A file named `util.sh` or `run.md` is cheap for a human who remembers context, but expensive for a fresh agent reading a directory listing. Vague names also make drift harder to spot — two scripts that do similar things with similar names blur together.

## Idea
1. Add a warning-only name check to `check-framework.sh` (or a small backing script in `scripts/`).
2. Flag: names that are single-word generics (`util`, `helper`, `run`, `test`, `common`), names that don't hint at their action or domain, temp-looking files outside a temp path, and names that shadow or nearly duplicate another file.
3. Emit a warning with a pointer to a better naming pattern — do not block on the warning.
4. Optionally: flag files that have been in temp paths past a defined age.

## Guardrails
Must not block legitimate legacy files. Warnings only — no hard failures. The check should be skippable for known exceptions.

## Likely home
`check-framework.sh` warning section + small backing script in `scripts/`. No new persona needed.

## Done when
Running `check-framework.sh` on a framework with vague names produces a readable warning list with suggested better names. Running it on a well-named framework produces no warnings. The check does not block the build or run.
