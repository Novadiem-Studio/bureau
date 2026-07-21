# Workflow: docs-reconcile

**When to use:** Plan/status docs (a `plans/todo/NN-*.md`, prompts README, INDEX, roadmap
table) or target-repo ADR status/decision records (`docs/adr/`) have drifted from code ground
truth — work progressed via direct commits, a revert, or renumbered migrations, and the docs
still describe the old state. The deliverable is updated docs, not code.

**When NOT to use:** docs that are wrong because the *code* is wrong — fix the code first, reconcile the docs after ground truth is stable. Not for spec/plan docs that haven't been committed yet.

**Type:** mixed
**Inputs:** the target repo(s), the list of doc files suspected stale, and any known drift
signals (commits, migration numbers, reverted features).
**Outputs:** corrected doc files in the target repo (committed on user go), plus
`ground-truth.md` in the run dir recording what was verified.
**Leans on skills:** the target project's orientation skill (e.g. `orchardly`,
`monorepo-orientation`) for repo layout; nothing else.

## Steps

1. **Analizer 2000** (Survey, **standard**, fresh context) — read ONLY the repo, not the docs' claims: git history since the docs' last substantive edit, the migrations directory (numbers, names, header comments), routes/screens that exist, reverted commits (note what was reverted and keep the why if discoverable), and whether accepted ADR decisions are still reflected by code. No recommendations. → `<run dir>/ground-truth.md` (a flat, cited list of facts: migration table, shipped surfaces, reverts, open decisions visible in code, accepted ADR drift)
2. **The Architect** (Reconcile, **standard**) — read `ground-truth.md` + the named doc files; edit the docs in place to match ground truth, preserving each doc's conventions and voice. Rules: never invent a decision the code didn't make; where code answered an open question, record the answer and mark it resolved; where code and plan genuinely diverge, keep it listed as open, updated to current state; status markers (✅/🟡/⬜, "In progress") must match ground truth. For ADR drift, load `docs/conventions/adr-records.md`: create a new superseding ADR and update only the old ADR's `Status:` line, never the old body. → corrected doc files + a list of every doc change with its ground-truth citation
3. **The Challenger** (Critic, round 1, **strong**, fresh context required) — cold-review the edited docs against the repo itself (NOT `ground-truth.md` — it re-derives, so a survey error can't propagate). Flag: doc claims still contradicting the repo, invented decisions, stale status markers, broken internal references, accepted ADRs whose decisions no longer match code and have no superseding ADR. → FINDINGS block
4. **The Conductor** (**standard**) — adjudicate: route blockers back to the Reconcile agent (The Architect) (max 2 loops), judge warnings → `<run dir>/log.md`
5. **The Conductor** (**standard**) — close out: show the user a summary diff of the doc changes; on go, commit in the target repo (docs-only commit, current branch); then, as the **final** close-out action, run `scripts/account-run.sh <RUN_DIR>` and set `state.json#accounting` per `docs/run-accounting.md` → committed docs, updated `state.json`
