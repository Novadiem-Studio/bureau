---
priority: 03
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: doc-sync-pass
---

# 03. Doc-sync pass after script/runbook changes

## One-liner
After any meaningful script or runbook change, a least-privilege sync agent reads the updated executables and writes only the directive docs/runbooks to match, then a cold Challenger verifies they agree.

## Problem
Execution code and runbooks drift. When a script is fixed or extended, the runbook describing it often is not updated in the same pass. Agents then follow stale instructions even when the underlying script is correct. This breaks trust in the doc layer and forces agents to reason from code instead of authoritative docs.

## Idea
1. After meaningful changes to scripts or runbooks land, trigger a doc-sync pass.
2. A sync agent (least privilege: read-only on executables, write-only on directive docs) reads the changed scripts and tests.
3. The sync agent updates the corresponding runbooks, docs, or directives to match.
4. A cold Challenger reviews the updated docs against the executable ground truth and flags any remaining gaps.

## Likely home
`docs-reconcile` workflow variant first. If the pattern repeats across enough run types to justify it, promote to a dedicated persona. Could also be a mandatory close-out step in `operational-build` and `runbook-repair`.

## Done when
After a script change, the matching runbook agrees on: inputs, commands, outputs, done criteria, failure behavior, and observability signals. The Challenger confirms agreement. No manual doc update required.

## Open questions
- Should this be a standalone workflow pass or a mandatory subsection of `operational-build`?
- How should the framework detect which docs correspond to which scripts (naming convention, manifest, or inference)?
