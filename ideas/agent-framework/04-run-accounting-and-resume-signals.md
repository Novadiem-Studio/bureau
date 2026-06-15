---
priority: bundle-04
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: run-accounting-and-resume-signals
source-ideas:
  - source-notes/05-per-run-accounting-ledger.md
  - source-notes/15-git-log-commit-summary-resume-signal.md
---

# 04. Run accounting and resume signals

## Purpose

Make a finished run easier to evaluate and resume: what it cost, which roles ran, which model
tiers were used, how efficient the workflow was, and what the git history can tell a fresh
session.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `05-per-run-accounting-ledger` | Structured run accounting and studio-level trends. |
| `15-git-log-commit-summary-resume-signal` | Standardized commit messages as a supplementary resume signal. |

## Dependency

Run this after Bundles 01 and 02. Accounting is most useful when runs have stable phases,
failure signatures, regression fixtures, and close-out conventions.

## First implementation slice

1. Define `templates/accounting.json` with confidence labels:
   - exact;
   - estimated;
   - inferred;
   - unavailable.
2. Add `scripts/account-run.sh <RUN_DIR>` that reads:
   - `state.json`;
   - `log.md`;
   - `model-routing.json`;
   - usage snapshot if present.
3. Emit `RUN_DIR/accounting.json`.
4. Add a close-out convention: the Conductor runs accounting after a completed run, or records
   why accounting is unavailable.
5. Add commit message guidance for execute workflows, but keep it supplementary:
   `state.json` remains authoritative.

## Later implementation slice

- Aggregate `RUN_DIR/accounting.json` into `output/studio/accounting-ledger.json`.
- Give Tally a read-only accounting errand only after the script schema stabilizes.
- Add `scripts/resume-from-git.sh` to summarize framework-tagged commits.
- Add Ministry of Flow surfaces once the ledger has enough real data.

## Done when

- A completed run produces `accounting.json` or a clear unavailable reason.
- Accounting fields never appear without confidence labels.
- A fresh session can use git history as a quick primer without replacing `state.json` and
  `log.md`.
- Workflow sizing decisions can reference actual pass counts and routing choices.

## Risks

- False precision. Estimated cost is fine; unlabeled precision is not.
- Tally must stay read-only. The script or Conductor writes the packet.
- Commit conventions must not fight target-project norms. Use prefixes/trailers only where
  the target repo allows them.

