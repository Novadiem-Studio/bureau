# Improving the agentic workflows

A working list of where the workflow layer can get stronger, written 2026-06-14 after a
read-through of the then-registered workflows (`workflows/*.md`), the orchestrator protocol
(`agents/orchestrator.md`), and the registry parser the new Ministry of Flow (aka Logistics) Workflows tab runs
on (`mof/lib/workflow-parser.ts`).

Scope is the **workflows themselves** — coverage, structure, handoffs, triage — not the
visualizer. Each item names the file it comes from and proposes a concrete change. The
priority table at the end is the short version.

---

## 1. Coverage — workflow gaps now closed

`CLAUDE.md` says "a bug fix, an iOS build, and a new feature run very different workflows,"
and `feature.md` explicitly excludes its own use for "one-line bug fixes or operational
builds — those get lighter workflows." Those lighter workflows now exist in the registry.

| Workflow | Type | Status |
|---|---|---|
| `bug-fix` | mixed | Registered; routes known defects through reproduce → locate → worktree fix → cold diff review → dev verification. |
| `operational-build` | execute | Registered; gives the `execute` type a runbook-driven ops/build path. |
| `code-review` | mixed | Registered 2026-06-15; standalone cold review for diffs, branches, PRs, and uncommitted changes. |

Remaining coverage work should start from real missed triage cases, not from this old gap list.

---

## 2. Make step lines machine-readable

The Workflows tab parses each step's **leading line** for the agent (a bold span matching a
known name) and the tier (a standalone bold token). Several real steps hide that information
where the parser — and a human skimming — can't see it. These render as agent-less,
tier-less nodes today.

| File | Step | Problem | Fix |
|---|---|---|---|
| `execute-plan.md` | 6 | `**Build, part by part** — The Conductor runs…` — agent is prose, not a bold span | Lead with the agent: `**The Conductor** — build, part by part…` |
| `execute-plan.md` | 7 | `**Close out** (The Conductor) —` — agent in parens | Same — bold the agent first |
| `docs-reconcile.md` | 1–2 | `**Survey (spawn, tier: standard).**` — tier is inside a compound label, not a standalone token | Split it: `**Survey** (spawn, **standard**) —` so `standard` is its own bold span |
| `docs-reconcile.md` | 4–5 | `**Adjudicate (Conductor).**` / `**Close out (Conductor).**` — agent inside the label | Bold the agent name on its own |
| `docs-reconcile.md` | 1 | "A fresh-context agent reads…" — anonymous spawn, no cast identity or tier | Name it. Even a generic role (the Witness, an analyst) gives it a tier and traceability. |

This cuts both ways. The cheap fix is to **standardize step authoring** — a one-paragraph
"how to write a step" convention added to `define-workflow` and the top of `index.md`: lead
with `**Agent Name**`, put the tier as its own `**standard**`/`**strong**` token, use
`→ target` for outputs. That makes every workflow self-describing for free.

The alternative is to keep teaching the parser every prose variant (parens, compound labels,
anonymous spawns). That's a losing game — the convention is cheaper and helps human readers
too. Recommend the convention; treat parser leniency as a fallback, not the plan.

---

## 3. Register every agent the workflows actually spawn

`AGENT_ALIASES` in the parser is the single map from prose name → role key → cast id. Three
agents that workflows spawn are missing from it, so their nodes go dark:

- **The Coupler** — spawned in `execute-plan.md` step 6 ("Coupling pass"), has its own
  `agents/coupler.md` and a policy entry in `config/model-policy.v2.json`, but no alias and
  (check) no `society-cast.json` member. It's a first-class build-party agent that's
  invisible to the registry.
- **Scoot** and **Tally** — the shop droids (`agents/scoot.md`, `agents/tally.md`) for odd
  jobs. If any workflow names them, they need aliases too.

Fix: add the three to `AGENT_ALIASES` and confirm each has a `society-cast.json` entry (or a
deliberate `castId: null`, like the Witness). This is a five-line change that closes a
real visualization gap and forces the question "is every spawnable agent actually in the
cast?"

---

## 4. Strengthen the existing pipelines

The bones are good — the two-round Challenger, fresh-context isolation, the production-boundary
hard stop, the tier-escalation discipline already in `orchestrator.md`. Increments:

**Carry acceptance criteria forward as a checklist.** The Analyst writes requirements; the
Challenger reviews "cold." But there's no explicit, testable acceptance list that travels
from Analyst → Challenger → coder → final review. Each agent re-derives "is this right?"
from prose. Proposal: the Analyst ends `spec.md` with a numbered **Acceptance criteria**
block; the Challenger checks against it by number; the Spellwright's prompt checkpoints cite
the criteria they satisfy. Turns "review cold" into "review against a contract."

**Define the escalation path on a failed loop.** `max_critic_loops` (default 2) plus a
`[CHECKPOINT]` on exhaustion is good, but the checkpoint asks the human cold. Add one
automatic move before the human: when a producer fails the Challenger twice at its routed
tier, **re-run the producer once at the next tier up** (`standard → strong`), then
checkpoint if that also fails. `orchestrator.md` already endorses "escalate when a handoff
is thin" — this makes it a defined step in the loop instead of a judgment call.

**Let the feature pipeline overlap where it's safe.** `feature.md` is strictly sequential.
Most of it must be — handoffs depend on the prior artifact — but the Cleric's "is a UI
needed?" brief (step 5) doesn't depend on the Challenger's round-1 findings (step 4) and
could run alongside it. Small wall-clock win; only worth it if a run feels slow. Note it,
don't force it.

---

## 5. Close the resume/handoff reliability gaps

`state.json` is the machine-readable resume anchor; `log.md` is the human narrative. Nothing
keeps them consistent, and a drift between them is exactly what breaks a resume.

- **Validate state on resume.** A tiny `scripts/check-state.sh` that asserts `state.json`'s
  `phase` matches the last phase logged in `log.md`, and that `phases_complete` is a prefix
  of the actual pipeline. Run it at the top of a resumed session before doing anything.
- **Structure the handoff, not just the prose.** Agents pass context by writing to shared
  files and the next agent re-reading them. `carried_items` and `open_questions` in
  `state.json` are the closest thing to a structured handoff, but they're filled ad hoc.
  A required three-line handoff footer per agent — *consumed / produced / passing forward* —
  would make dropped context visible instead of silent.
- **Auto post-mortem per run.** The Witness summarizes across runs; nothing captures a
  single run's own lessons: how many critic loops, where a tier was over- or under-provisioned,
  what the Challenger caught. A one-block append to `log.md` at close-out feeds both the
  model-routing experiments (`config/model-experiments/`) and future workflow tuning.

---

## 6. Make triage harder to get wrong

Triage is the Orchestrator reading `index.md` and matching the task against the "When to
use" column by judgment. A mis-triage is expensive (running `feature` on a one-line fix).
Two cheap guards:

- **Add a "When NOT to use" line to each workflow file.** `feature.md` has one inline
  ("NOT for one-line bug fixes"); the others don't. The negative case disambiguates faster
  than the positive one.
- **Add a few-shot triage table to `index.md`** — five or six concrete `task → workflow`
  examples ("Fix a crash on login → bug-fix"; "Turn plans/todo/50-*.md into prompts →
  execute-plan"). Anchors the LLM judgment that triage rests on.

---

## 7. Right-size each agent's context — enough, never extra

This is the highest-leverage item and the one most worth real effort. A subagent's output is
only as good as what it was handed: too little and it guesses; too much and it anchors on
noise, spends tokens re-reading, or — worst for the Challenger — sees something that defeats
the point of spawning it fresh.

The framework already has the right instincts. The spawn template says "Read your inputs
(absolute paths — **only what your role needs**)" (`orchestrator.md:89`). Existing-project
mode says "Don't make an agent read the whole workspace — you hold the cross-repo map, each
agent holds its corner" (`orchestrator.md:330`). Scoot and Tally exist so odd jobs don't
inherit the Conductor's opus context. The bones are there. What's missing is making context
a **declared contract per role** instead of a choice the Conductor improvises each spawn.

### The leaks today

**The default over-shares.** The spawn template's example inputs are `spec.md` *and*
`plan.md` for everyone (`orchestrator.md:90-91`). The Analyst runs before `plan.md` exists.
The Cleric's "is a UI needed?" brief doesn't need the data-model internals. The template
normalizes "paste both big docs," and the "only what your role needs" caveat is one line
fighting the worked example.

**Whole files when a section would do.** `spec.md` accretes Requirements + Architecture
(+ acceptance criteria, if §4 lands). As it grows, every downstream spawn re-ingests all of
it. The Spellwright needs the approved plan and the spec it implements — not the full file
each time. Passing whole artifacts when an agent needs one section is the most common leak.

**The Challenger's cold review is only as cold as its inputs.** A fresh context window
guarantees it didn't *watch* the design get argued — but coldness dies the moment the
Conductor pastes `log.md` (where the design was defended) or round 1's findings into the
round-2 spawn. The template doesn't do this by default, which is good, but nothing
*forbids* it. The Challenger should receive the artifacts under review plus the acceptance
criteria, and explicitly **not** the rationale, the decision log, or the prior round's
findings — those anchor it toward agreement.

**Existing-project mode has the biggest blast radius.** "Work in sub-app X" still lets a
coder `grep` the whole monorepo and drag in irrelevant context. The boundary is stated but
soft.

**Cheap spawns under-context worst.** Scoot (haiku) and "a fresh-context agent" fill gaps
poorly. A thin prompt that omits the return shape or the one relevant path costs more in a
re-run than the tokens it saved.

### The fix — context as a per-role contract

**1. Give every `agents/<role>.md` an Inputs contract.** A short, explicit block: the
minimal artifacts (and *which sections*) the role reads, and a "does NOT receive" line for
the tempting-but-wrong ones. The sharp example:

```
## Inputs
Reads:  spec.md § Requirements, § Acceptance criteria; plan.md (full)
Does NOT receive:  log.md, prior Challenger findings, the Architect's design rationale
                   — coldness depends on it. If you were handed these, flag it and stop.
```

**2. Make the Conductor pass the declared inputs, not the default pair.** Replace the
template's "spec.md / plan.md" example with "the role's declared Inputs contract," plus a
one-line discipline: *pass exactly what the contract names; if you're tempted to add more,
name the specific decision in this agent's task that needs it — if you can't, don't.*

**3. Pre-build a scope manifest for existing-project spawns.** The Conductor holds the
cross-repo map; spend a cheap **Tally** pass to turn it into a per-agent manifest — the exact
dirs/files in play and the one local `CLAUDE.md` to load — and hand the coder *that*, rather
than a sub-app name and trust. Cheap to build, and it converts "each agent holds its corner"
from advice into a handed artifact.

**4. Pass the contract into consumer build spawns.** A coder building the consumer half of a
seam needs the produced contract up front. The Coupler catches a broken seam after the fact;
handing the seam definition into the consumer spawn prevents the guess. (Ties to §3.)

**5. Lean on the structured handoff (from §5) to stop re-reading.** Once each agent ends with
a *consumed / produced / passing-forward* footer, a downstream agent can read the handoff plus
the one section it changes — not the entire upstream history. The handoff is the summary that
lets the next context stay small.

The audit hook: have each agent's handoff state what it actually consumed. Over a run you can
see where an agent was handed more than its task touched — that's the over-context to trim
next time, and it feeds the per-run post-mortem in §5.

---

## Priority

Status note: this is the original backlog ordering; rows that have since landed are left here
for history and marked as done.

| # | Change | Effort | Payoff |
|---|---|---|---|
| 1 | Per-role **Inputs contract** in every `agents/*.md` + Conductor passes only that (§7.1–7.2) | M | Highest — better output, fewer tokens, keeps the Challenger cold |
| 2 | Acceptance-criteria checklist carried Analyst → Challenger → coder (§4) | M | High — turns cold review into review against a contract; also the Challenger's core input |
| 3 | Done: write a `bug-fix` workflow (§1) | M | Completed — registered in `workflows/index.md` |
| 4 | Standardize step authoring (bold agent, standalone tier, `→` output) + back-fill the six steps (§2) | S | High — every workflow self-describes; viz accuracy for free |
| 5 | Scope manifest (cheap Tally pass) for existing-project spawns (§7.3) | M | High — biggest over-context blast radius |
| 6 | Structured handoff footer: consumed / produced / passing-forward (§5, §7.5) | S | High — stops downstream re-reading; the audit hook |
| 7 | Add The Coupler / Scoot / Tally to `AGENT_ALIASES` + cast (§3) | S | Medium — closes visible registry gaps |
| 8 | Defined tier-escalation step on a failed critic loop (§4) | S | Medium — fewer cold checkpoints to the human |
| 9 | `check-state.sh` resume validation (§5) | S | Medium — protects the resume path |
| 10 | Done: decide the `execute` type's fate (`operational-build` or drop it) (§1) | S | Completed — `operational-build` is registered |
| 11 | Per-run post-mortem block + triage examples + "when NOT to use" (§5, §6) | M | Medium — compounding, feeds routing experiments |

Do §7 first. Right-sizing context is the change that makes every other agent better at once,
and the Inputs contract is the artifact the acceptance-criteria work (item 2) and the
existing-project scope manifest (item 5) both build on. With the coverage gaps in §1 closed,
the next strongest live improvements are scope manifests, step-line cleanup, and resume
validation.
