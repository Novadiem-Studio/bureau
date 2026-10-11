# Battle-test: bureau-lite

**Canon surface touched:** `workflows/bureau-lite.md`, `workflows/index.md`,
`config/risk-tags.json`, `scripts/risk-tags.sh`, `scripts/run-start.sh`,
`scripts/preflight-artifacts.sh`, `templates/state.json`
**Promotion to canon:** yes (new workflow row; `docs/conventions/canon-promotion.md`)
**Status:** 5 cases. Cases 1-4 executed against the landed script and config; case 5 is a
walkthrough of the written downshift procedure, since no live run has downshifted under it yet.

## Run 2026-10-11 (promotion)

Cases 1-4 ran `scripts/risk-tags.sh` on scratch repos built to mirror the shape of rheo-stream's
`20261010-upwork-collector` units. The same guarantees are pinned as regression fixtures
314-319. Case 1's first execution over-fired: a plain jobs-list template tripped `concurrency`
through a `jobs?` path pattern, which in a jobs-domain app would flag nearly every unit. The
pattern was narrowed to scheduler, cron, celery and worker locations, and the case re-ran clean.
That fix is in this PR.

| Case name | Input description | Expected outcome | Actual result |
|-----------|------------------|-----------------|---------------|
| Credential collector, six units (typical) | A jobs app gains an Upwork collector, built as six units: 01 jobs-list view + template, 02 OAuth callback with PKCE verifier, 03 refresh-token store with encryption, 04 launchd plist scheduling the collector, 05 a plain model field, 06 a view test. Each unit is its own commit; `risk-tags.sh --base <parent>` runs per unit. | 01, 05 and 06 clean (exit 0, shipped on tests + CodeRabbit). 02 `oauth-auth`, 03 `tokens-secrets`, 04 `concurrency`, each exit 1 so the Challenger reviews them. No escalate. | pass (second run) — 01/05/06 clean, 02/03/04 review with the expected single tag each. First run: 01 over-fired on `jobs.html` (`concurrency` path `jobs?`); pattern narrowed, re-run clean. |
| EDGE: diff shapes that fool naive parsing | (a) a removed SQL comment `-- legacy password column`, shown in the -U0 diff as `--- legacy ...`; (b) a README naming OAuth, secret, Stripe, DROP TABLE and webhook; (c) `DELETE FROM` in application code vs. the same statement in an alembic revision. | (a) `tokens-secrets` fires on removed line 2, the parser does not take it for a file header; (b) clean, README listed in `files_ignored`; (c) app code does not escalate, the alembic revision does (exit 3). | pass — fixtures 315 and 317. |
| FAILURE MODE: money and destructive migration mid-build | (a) a unit adding `fee = job.amount_cents * 0.1` in `app/upwork/fees.py`; (b) a unit appending `ALTER TABLE users DROP COLUMN legacy` to a migration. | Both exit 3 (`money`, `destructive-migration`): dispatch stops, `genuine-fork` signal 6, Robin upshifts or waives and the unit is still reviewed. | pass — (a) exit 3 `money`; (b) exit 3 `destructive-migration` (fixture 314). |
| FAILURE MODE: a run tries to loosen its own triggers | The run branch rewrites `project-context.md`'s `risk_tags` block to `{"tags": [], "ignore_paths": [".*"]}`, then adds an `httpx` call; separately the same block, a `line_scope` on a default tag, and a raise-to-escalate are passed explicitly; separately `run-start.sh --workflow bureau_lite`. | The run-branch block is not read (the default source is `git show <base>:project-context.md`), so `network-egress` still fires; the explicit loosening blocks exit 2 (fail closed, reviewed); the raise is honoured (exit 3); the typo'd workflow id is refused before any run dir exists. | pass — fixtures 316 and 318. |
| EDGE: downshift of a running build (walkthrough) | An `execute-plan` build at prompt 09 of 25. Robin tells the Delegate the work is low risk and to lighten the review. | The Delegate logs `WORKFLOW-SHIFT: execute-plan → bureau-lite from unit 10` with Robin's words through `log-append.sh` and relays it; prompt 09 finishes under the old cadence; the Conductor appends `{"from":"execute-plan","to":"bureau-lite","effective_from":"10",...}` to `state.json#workflow_shifts`, leaves `workflow` as `execute-plan`, and runs `update-runs-index.sh`; from 10 on each prompt gets a `risk-tags/<NN>.json` record and only flagged ones a Challenger; integration gates unchanged; the close-out coverage line starts `from 10:`. Neither the Delegate nor the Conductor could have made the shift without Robin. | pass (walkthrough) — every step above is written in `workflows/bureau-lite.md § Downshifting a running build`; `templates/state.json` carries `workflow_shifts: []` (fixture 318). Not yet observed on a live run. |
