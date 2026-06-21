---
priority: bundle-10
status: idea
suggested-workflow: feature
suggested-run-slug: planning-loop-reduction
relates-to: bundle-03 (planning decision quality gates — this is its direct follow-up); bundle-09 (complementary — 09 makes loops cheaper, this makes them fewer)
origin: Bundle 04 (run-accounting) post-mortem, 2026-06-20
outcome: a comparable feature run needs measurably fewer correction loops than Bundle 04 — which took ~4 prompts-stage HOLD rounds plus three pre-Challenger design holds and a workflow-ownership rewrite
---

# 10. Planning loop reduction — shift catches left

Bundle 09 (the delegate) makes each correction loop *cheaper* to review. This bundle makes the
loops *fewer*. The two are independent and complementary: 09 lowers the cost of a review; this
lowers how many reviews a run needs.

Origin: the Bundle 04 (`run-accounting-and-resume-signals`) post-mortem. The sharpest outside
reading (DeepSeek) found the root cause in the run log; a second (Grok) found one real shift-left.
This note keeps only what was **verified against the source tree** — three changes — and records
what was rejected so a run doesn't re-derive it.

## The problem (from the Bundle 04 log)

The expensive loops were not the Challenger finding things. They were **Analyst↔Architect drift**:

- The Analyst writes Requirements, hands off, and never sees the Architecture again
  (`workflows/feature.md:28-39`: Analyst → Architect → checkpoint → Challenger; **no Analyst step
  after the Architect**).
- The Architect, constrained from editing Analyst-owned Requirements, added a "supersedes"
  addendum — so the spec's later ACs contradicted its own FRs. That cost the run's most expensive
  loop: Analyst rewrites Requirements in place → Architect reconciles Architecture/plan → fresh
  Challenger.
- Two more findings (actual_model absent-vs-null, run_date format) were the same class:
  requirements, architecture, and ACs telling slightly different stories.

The framework already *catches* these — at round 1 the cold Challenger checks "Contradictions —
requirements and architecture conflict" (`critic.md:67`) and stale supersedes-content
(`critic.md:71`). The point is not that they're uncatchable. It's that catching them **at the
Challenger costs a full design → review → correction loop**, when catching them at the owner costs
one cheap pass. Shift the catch left.

## The three changes

### 1. Analyst reconciliation pass after the Architect

Add one workflow step after the Architect, before the design-model checkpoint: re-spawn the Analyst
(`standard` tier) to read the Architecture against the Requirements and **fix drift in place**.
Three questions: does the design implement every requirement; did the Architect interpret anything
differently than intended; did the Architect make new assumptions that belong in the spec. Output:
the Analyst edits `spec.md` Requirements where they drifted and writes a short `RECONCILED:` note to
`log.md` naming what it changed (or "no drift").

Why it works: the Analyst *owns* Requirements, so it fixes drift directly — collapsing the
find → route → rewrite → reconcile chain into one pass. It targets the verified root cause.

Enforcement (passes gate-theater): the pass is a producer obligation (a workflow step); Challenger
round 1 then verifies consistency, which it already does (`critic.md:67`), now against a named
artifact. A missing `RECONCILED:` note is a Warning.

Scope (passes the machinery test): feature / greenfield runs that produce both Requirements and
Architecture. Not bug-fix (no separate Requirements/Architecture split). One `standard`-tier pass;
it pays for itself the first time it prevents an Analyst-rewrite + Architect-reconcile double loop.

### 2. Real-log reconciliation for self-observing features

When a feature parses or observes the framework's own output (`log.md` headings, `state.json` keys,
spawn events, run-dir shapes), the spec must carry an **"Observed-behavior reconciliation"** section:
cite 2–3 real recent run logs and name where reality deviates from the idealized template. Its
absence is a **Challenger Blocker**, enforced exactly like the greenfield-assumption-table check
(`critic.md` FR 11).

Why: Bundle 04's two biggest round-1 blockers were both this — the parse contract assumed
`## … Spawned X → complete`, but real logs use many heading shapes and a session-limit spawn
produces no heading at all. The Challenger caught both by reading real logs ("of 13 'Spawned'
mentions, only 7 are headings"). Moving that reconciliation to the producer saves the loop.

Narrow trigger (machinery test): fires **only** when the spec describes reading/parsing
framework-internal artifacts. A feature that touches no framework output never needs it. Challenger
trigger: spec describes parsing framework artifacts AND no Observed-behavior section → Blocker.

This folds into #1: for a self-observing feature, the Analyst's reconciliation pass produces this
section.

### 3. Artifact-consistency pre-flight before the Challenger

A cheap mechanical check — a script, or a Scoot (`haiku`) pass — run before Challenger round 1 that
verifies:

- expected artifacts exist (`spec.md`, `plan.md`; `prompts.md` when the workflow reaches it);
- every FR in the spec is mentioned in the plan at least once;
- every plan phase has a corresponding prompt (round 2);
- no dangling cross-references (e.g. "see EC 14" where no EC 14 exists — a real Bundle 04 warning);
- **mechanical code invariants** in any embedded snippet or fixture — schema keys present, `jq` paths
  valid, no forbidden `jq -e` gate, Bash BSD/GNU portability, fixture shape. The Bundle 04 defects
  were overwhelmingly mechanical; a linter catches them before any model reads the artifact (Codex
  retro: "machines should catch those before either model reads anything").

Why: it shifts the Challenger from spending `strong`-tier tokens on "what's missing / what doesn't
resolve" to evaluating what's present. **Script-enforced**, so it passes the gate-theater rule
outright — no Conductor discretion.

Distinct from `preflight.sh` (Bundle 01a), which checks the *execution environment*; this checks
*artifact cross-references*. Could live as `scripts/preflight-artifacts.sh` or a Scoot pass — decide
in the run. Caveat: prose cross-reference resolution is fuzzy, so a Scoot pass is more robust than
brittle regex for the FR→plan→prompt mapping; pick per check.

## From the Bundle 04 retro (Codex) — two more, at the source

Codex's end-of-run retro surfaced the biggest loop driver of all, and it isn't a gate — it's what
goes into `prompts.md`.

### 4. Prompts carry contracts and tests, not production code

Most of the Bundle 04 loops weren't design problems. `prompts.md` embedded hundreds of lines of
near-production shell, and reviewers kept checking pseudo-code as if it were executable — most of the
twenty build-breakers were defects in *code that shouldn't have been in the prompt at all*. The fix
is a Spellwright rule: a prompt specifies the **contract and the executable tests** — signatures,
validation rules, the fixtures that must pass — and lets the build agent write the implementation.
Reviewers then check contracts and test coverage, not hand-written shell; CI catches mechanical
defects against real execution, where they belong. This collapses the most expensive class of loop at
its source, and it's why the mechanical-invariant linter (change 3) has less to do than it sounds —
there should be little hand-written code in the prompt to lint.

### 5. One consolidated completion checklist before "complete"

The Bundle 04 log declared the run "complete," then "(corrected)," then "(second correction)," then
"(third correction, final)" — several premature completions. Require a single checklist the Conductor
must satisfy before declaring done: every AC mapped, every Challenger blocker closed in the artifact
text, the artifact-consistency check green, the mechanical linter clean. One gate, checked once,
instead of discovering incompleteness after the fact.

## Already exists — do not rebuild

- Edge cases / failure modes — `analyst.md:79` ("Edge Cases & Failure Modes").
- Design-model checkpoint as a mandatory gate with a structured summary — `orchestrator.md:477`,
  `architect.md:86`.
- Simplest-Model Baseline with a per-mechanism forcing requirement — `architect.md:80` (prose).
- Recurring-failure learning loop — Bundle 02 (`conventions.md:382` failure signatures, `:429`
  recurrence rule).
- The cold Challenger already checks requirements↔architecture contradictions and stale content —
  `critic.md:67,71`.

## Considered and rejected — do not re-propose

- **Pipe-delimited SPAWN-EVENT** — the run explicitly rejected delimited for JSON to avoid quoting
  edge cases in agent names (e.g. `The Architect (opus, model-correction)`). A delimited format
  reintroduces that bug.
- **Objective Blocker criteria** — removes the deliberate split where the Challenger *rates* and the
  Conductor *decides* (`critic.md:325`); severity needs judgment; adjudication wasn't a major loop
  source in this run.
- **Conductor-run "Pre-Challenger Readiness Gate" checklist** — a Conductor-discretionary gate is
  gate-theater (`index.md:54`): the Conductor has the standing ship bias. The need is met instead by
  #1 (producer obligation) + Challenger verification.
- **Splitting the Challenger into consistency + depth passes** — trades read-cost (two cold spawns
  re-reading the same artifacts) for tier-cost; unclear net win; partly duplicates the
  round-1/round-2 split.

Deferred refinements (low value): a structured Simplest-Model Baseline *table* (the forcing-
requirement obligation already exists in prose), and a "three things that could be simpler" line in
the Design-Model Summary.

## Doctrine constraints (every gate here obeys them)

- **Gate-theater** (`index.md:54`): each gate is script-enforced (#3) or Challenger-checkable
  (#1, #2). None is Conductor-discretionary.
- **Machinery test**: each has a narrow trigger and is justified by a recurrence in real runs, not
  added speculatively. Bundle 02's recurrence rule (`conventions.md:429`) is the formal basis —
  Analyst↔Architect drift has recurred, so a fix is owed.

## Done when

- A feature run runs an Analyst reconciliation pass after the Architect; drift is fixed in place and
  a `RECONCILED:` note names what changed (or "no drift").
- A self-observing feature's spec carries an Observed-behavior reconciliation citing real run logs,
  and the Challenger Blocks its absence.
- An artifact-consistency check runs before Challenger round 1 and reports missing artifacts,
  unresolved cross-refs, any FR with no plan mention, and any plan phase with no prompt.
- **Outcome (falsifiable):** the next comparable feature run needs measurably fewer correction loops
  than Bundle 04 (≈4 prompts-stage HOLD rounds + three pre-Challenger design holds + a
  workflow-ownership rewrite). If loop count doesn't drop, the gates didn't earn their place.

## Relationship to other bundles

- **Bundle 03** (planning decision quality gates) — this is its direct follow-up: same surface
  (spec/plan quality before build), same enforcement pattern (Challenger checks like the greenfield
  table).
- **Bundle 09** (delegate) — complementary and independent. 09 makes loops cheaper to review; this
  makes them fewer. Order doesn't matter; if both land, the delegate reviews a process that already
  produces fewer loops.
- **Bundle 02** (learning loop) — its recurrence rule is what justifies promoting these.
