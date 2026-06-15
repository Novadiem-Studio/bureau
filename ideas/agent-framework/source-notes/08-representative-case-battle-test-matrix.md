---
priority: 08
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: representative-case-battle-test-matrix
---

# 08. Representative-case / battle-test matrix

## One-liner
Before promoting a prompt or automation workflow to canon, run it against a small predefined set of representative inputs and require a passing result.

## Problem
Prompts and automation workflows get promoted to canon after passing one case — the one they were built for. They often fail on the second or third real use because the test set was not representative. There is no structured gate that says "this workflow has survived a realistic spread of inputs."

## Idea
1. For each prompt or automation workflow being promoted, define a battle-test matrix: a small set (3–5) of representative input cases, including at least one edge case and one failure mode.
2. Run the workflow against all cases. Record pass/fail and any noteworthy behavior per case.
3. A workflow or prompt only graduates to canon if it passes the full matrix, or if Robin explicitly accepts a known failure with a note explaining why it is acceptable.
4. The matrix lives alongside the workflow or prompt as a plain text file (e.g., `battle-test.md` in the run dir or workflow folder).
5. On subsequent runs, re-run the matrix to catch regressions before the next promotion.

## Likely home
Close-out step in `execute-plan` and `operational-build` workflows. Battle-test matrix file convention alongside workflow definitions. Could be enforced by a Challenger step that asks "what are the representative cases and have they been tested?"

## Done when
Promoting a workflow to canon requires a battle-test matrix with recorded results. A Challenger pass checks that the matrix exists and is non-trivial. Robin can see which cases passed and which were knowingly waived.

## Open questions
- How many cases is enough? 3 and 5 are both arbitrary — what makes a matrix representative vs. padded?
- Should the matrix be defined by The Architect during planning, or by The Spellwright when writing prompts?
- How should the system handle workflows where the input space is hard to enumerate (e.g., open-ended generative prompts)?
