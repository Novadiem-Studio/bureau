# Workflow: docs-reconcile

**When to use:** Plan/status docs (a `plans/todo/NN-*.md`, prompts README, INDEX, roadmap
table) have drifted from code ground truth — work progressed via direct commits, a revert,
or renumbered migrations, and the docs still describe the old state. The deliverable is
updated docs, not code.
**Type:** mixed
**Inputs:** the target repo(s), the list of doc files suspected stale, and any known drift
signals (commits, migration numbers, reverted features).
**Outputs:** corrected doc files in the target repo (committed on user go), plus
`ground-truth.md` in the run dir recording what was verified.
**Leans on skills:** the target project's orientation skill (e.g. `orchardly`,
`monorepo-orientation`) for repo layout; nothing else.

## Steps

1. **Survey (spawn, tier: sonnet).** A fresh-context agent reads ONLY the repo, not the
   docs' claims: git history since the docs' last substantive edit, the migrations
   directory (numbers, names, header comments), routes/screens that exist, reverted
   commits (note what was reverted and keep the why if discoverable). Writes
   `<run dir>/ground-truth.md`: a flat, cited list of facts (migration table, shipped
   surfaces, reverts, open decisions visible in code). No recommendations.
2. **Reconcile (spawn, tier: sonnet).** Reads `ground-truth.md` + the named doc files.
   Edits the docs in place to match ground truth, preserving each doc's conventions and
   voice. Rules: never invent a decision the code didn't make — where code answered an
   open question, record the answer and mark the question resolved; where code and plan
   genuinely diverge (e.g. a planned rename not done), keep it listed as open, updated to
   the current state. Status markers (✅/🟡/⬜, "In progress") must match ground truth.
   Returns a list of every doc change with its ground-truth citation.
3. **Cold review (spawn The Challenger, `agents/critic.md`, tier: opus).** Fresh context.
   Reads the edited docs + the repo itself (NOT ground-truth.md — it re-derives, so a
   survey error can't propagate). Flags: doc claims still contradicting the repo, invented
   decisions, stale status markers, broken internal references. FINDINGS block as usual.
4. **Adjudicate (Conductor).** Route blockers back to the Reconcile agent (max 2 loops),
   judge warnings, log calls in the run dir's `log.md`.
5. **Close out (Conductor).** Show the user a summary diff of the doc changes; on go,
   commit in the target repo (docs-only commit, current branch). Update run `state.json`.
