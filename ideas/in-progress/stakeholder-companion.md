# Stakeholder Companion (project-agent, activated against real framework runs)

Date: 2026-06-14

## One-liner

project-agent's three jobs, finally built for real and pointed at a project the agent-framework
is building: tell a stakeholder where the project is at, answer their questions as the project's
knowledge base, and collect their feedback on aspects as those aspects get defined. The unlock is
that a framework-built project already emits structured run artifacts (`state.json`, `log.md`), so
status stops being a guess and becomes a read.

## Why this one (the dual-use logic)

Robin asked for something to build now that helps Douglas but is useful on other projects anyway.
This is project-agent's actual designed purpose (DESIGN.md, three jobs), and two things make now
the right moment:

1. **The agent-framework makes the hard job easy.** project-agent's status-broadcasting job
   originally assumed hand-curated activity lists or a filesystem watcher. When the tracked project
   is built by the agent-framework, the framework already writes a structured status record every
   run. "Where are we" becomes reading `state.json` plus summarizing the tail of `log.md`, not
   inferring from prose.

2. **There is unfinished business that proves it.** The round-2 questions for Douglas were mapped
   into project-agent's structured-feedback walkthrough as the first review, then sent as a PDF
   instead. The review never happened in the tool. The mechanism is reusable for every future
   review (discovery questions, spec sign-offs, milestone approvals), and the round-2 set is a
   ready first test case.

Useful for Douglas: a sponsor who wants to know where his project stands and answer Robin's open
questions without reading every doc. Useful for every project: every framework run emits the same
artifacts, so one companion works across all of Robin's runs.

## The three jobs

### Job 1: Status, from framework run artifacts (the unlock)

A framework run writes `output/runs/<run>/state.json`. Verified fields today: `project`, `phase`,
`phase_status`, `phases_complete[]`, `critic_loops` / `max_critic_loops`, `open_questions[]`,
`carried_items[]`, `checkpoints[]`, `decisions{}`, `git{}`, `last_updated`. Plus `log.md`, the
human narrative with the newest entry at the bottom.

Stakeholder status questions map straight onto those fields, mostly with no LLM in the loop:

| Question | Source | LLM? |
|---|---|---|
| Where are we / what phase | `phase` + `phase_status` + `phases_complete` | no |
| Is it blocked or waiting on me | `checkpoints[]` (awaiting "go"), `carried_items[]`, `open_questions[]` | no |
| Is it stale | now minus `last_updated` over 4h (Ministry of Flow (aka Logistics)'s threshold) | no |
| What changed / what just happened | summary of newest `log.md` entries | cheap |
| Why did we decide X | `decisions{}` + `decisions/` + `spec.md` | grounded Q&A |

The status facts are read, not generated. That is the deterministic, anti-hallucination answer
project-agent's ADR-005 wanted, available for free because the framework already emits structured
state. Only the "what changed" narrative needs the model, and it summarizes a real document and
cites the run's `log.md`.

### Job 2: Knowledge base (cited Q&A)

The same corpus (the project's docs and decisions plus the run's `spec.md` / `plan.md` / `log.md` /
`design/`) is the queryable knowledge base. Stakeholder asks a question, gets a cited answer, gets
a graceful "not in the project context" when it is not covered. This is the most structured corpus
project-agent will ever ground against, which makes it the right place to build its first real LLM
surface.

### Job 3: Structured feedback collection (the review that did not happen)

Walk the stakeholder through open questions one at a time as aspects get defined: prev / next /
skip / save, auto-save drafts, write answers back to a sidecar in the project corpus (git stays
the system of record), email Robin a digest.

- **First test case:** the round-2 questions for Douglas (`manage2retain-docs/docs/round2_questions_for_douglas.md`),
  the review that was mapped for v0.1 and then sent as a PDF instead.
- **Ongoing use:** every later round of "define this aspect, get the stakeholder's call" is another
  question set: Milestone 1 discovery questions, spec decisions, milestone sign-offs.

The tables for this (`question_sets` / `questions` / `answers`) already exist in project-agent's
schema. The walkthrough UI and routes do not.

## How it serves Douglas

- When M2R is built via the agent-framework, Douglas (sponsor, magic-link access) asks "where's my
  project at" and gets a true, current status: phase, what is waiting on him, what just shipped,
  with cited decisions.
- The round-2 review (and later discovery and milestone reviews) runs as a clean one-question-at-a-time
  walkthrough instead of a PDF round-trip, and the answers land back in the repo automatically.
- It is also the project-agent sales demo: a sponsor watching their own build through a grounded,
  honest, cited surface is the working proof of the platform's value, with no contractual
  entanglement (M2R ADR-001).

## How it serves every other project

- Every agent-framework run writes the same artifacts, so the status reader and knowledge base work
  across all of Robin's runs with zero per-project wiring.
- It is the conversational, stakeholder-facing sibling of Ministry of Flow (aka Logistics): Ministry of Flow (aka Logistics) is the visual
  read layer over runs, this is the ask-it-in-words and collect-feedback layer.
- The feedback walkthrough is content-agnostic: any project with open questions for a stakeholder
  reuses it.

## What exists vs what this builds

Honest split, verified against the code on 2026-06-14.

**Already built (reuse directly):**
- The framework run artifacts themselves (`state.json` fields above, `log.md`). Stable and real.
- Ministry of Flow (aka Logistics) already parses `state.json` / `log.md` across installs; its read pattern transfers.
- project-agent: corpus loader with audience filtering, magic-link auth, admin UI, full schema
  including `question_sets` / `questions` / `answers` / `changelog` and a `messages.citations_json`
  column.

**Not built yet (this idea builds it):**
- project-agent has no LLM layer at all: no chat route, no streaming, no OpenRouter call. Only the
  OpenRouter key and model settings exist in config. So Q&A and log summarization are net new.
- No run-artifact ingestion: project-agent does not read framework run dirs yet.
- No status reader (the `state.json` to facts mapping).
- No feedback walkthrough UI or routes (tables only).

So this is not pure assembly. It builds project-agent's first real AI surface, against the most
structured corpus available, which is the right place to start it.

## Out of scope (v1)

- HRIS ingestion and ML risk scoring (M2R-specific, separate work).
- The full typed knowledge graph (project-agent ADR-005 stays deferred; the `state.json` reader is
  its cheapest first instance, not the whole thing).
- Multi-run rollups for one project. Start with "newest run by mtime is the current run," matching
  how status is read today.
- The methodology-elicitation idea (capturing Douglas's retention frameworks). Separate concern,
  parked, not this.

## Technical direction (not decided here)

- Register a project's framework run dir (`output/runs/`) as part of its corpus so the loader picks
  it up alongside docs and decisions.
- Status reader parses the newest run's `state.json` into typed facts. Deterministic, no model.
- Log summarizer runs a cheap model over the newest N `log.md` entries, cites the file.
- Reuse Ministry of Flow (aka Logistics)'s 4h staleness threshold rather than inventing one.
- Consider a shared run-reader module that both Ministry of Flow (aka Logistics) and project-agent import, once both
  need it. For now, copy the pattern, do not prematurely extract.
- Build inside project-agent (fastest path to a Douglas-usable thing).

## Suggested phasing

1. `state.json` reader plus the project-home "where's this at" panel. Deterministic status, no LLM.
2. `log.md` summarizer for "what changed / recent activity," cited.
3. Cited Q&A over the run corpus plus project docs. project-agent's first real grounding surface.
4. Feedback walkthrough UI on the existing schema, run the round-2 set as the first review,
   write-back to sidecar, email Robin a digest.
5. Sponsor view (magic-link) for Douglas, with audience filtering on which fields are sponsor-safe.

## Open questions

- Newest-run-only vs run history for "where's the project at." Start newest.
- Which `state.json` fields are sponsor-appropriate. `checkpoints` ("waiting on you") clearly yes;
  raw `open_questions` / `carried_items` may be internal. Apply the audience discipline from
  project-agent ADR-001.
- Does the status reader live in project-agent or as a shared lib with Ministry of Flow (aka Logistics). Lean shared
  eventually; copy the pattern for now.
- How fresh does status need to be. Poll the run dir, or trigger on file change (the deferred
  watchdog from project-agent v0.1.5)?

## Relationship to existing work

- **Ministry of Flow (aka Logistics)** and the `society-desk-workflow-viz` idea: the visual read layer over runs. This
  is the conversational and feedback-collecting sibling. Share the parsing.
- **project-agent DESIGN.md** jobs 1, 2, 3 (Q&A, status broadcasting, structured feedback): this is
  those three jobs, made buildable by feeding them framework run artifacts and by reviving the
  round-2 review as the first feedback set.
- **project-agent ADR-005** (deferred knowledge layer): the `state.json` reader is the cheapest
  possible first slice of "deterministic facts over generation," free because the framework already
  emits the state. Does not supersede the deferral of the general graph.
- **The retired round-2-as-PDF decision** (DESIGN.md framing-shift note): this revives the
  walkthrough as the structured-feedback mechanism, now that there is a real reason to build it.
