# Tutoring Tool Concept: Homeschool Learning Companion

**Working Names:** TutorQuill, ScholarQuill, QuillTutor, LearningQuill
**Brand family:** Quill (sibling to MemoirQuill)

**Date:** 2026-06-18
**Author:** Robin (for Novadiem / Rheo ecosystem)
**Status:** Idea / Early Concept

## What this is
An agent-powered tutoring companion for homeschooling families. It replaces the
ad-hoc workflow Robin already uses with Claude for Arowyn (paste an assignment or
study guide, get tailored materials back) and adds structure: parent-ready printable
output, a per-child profile, and over time a mastery model that tracks what the kid
knows.

The validated core is the generation workflow plus great output. The long-term
differentiator is the structured pedagogy on top. Those are built in that order.

## Honest positioning
"Persistent memory" is not the moat. ChatGPT, Claude Projects, and Gemini all have
memory now, and a homeschool parent can already make a Claude Project per kid. The
defensible edge is the pedagogical structure: mastery tracking, spaced repetition,
curriculum alignment, and output a parent can print and hand to a child. That is what
we lead with, not "we remember your kid."

Competitors to be honest about: MagicSchool AI, Khanmigo, SchoolAI, Brisk, and "just
use ChatGPT." We do not win on raw model capability. We win on (a) output a parent can
use without editing and (b) continuity that one-off chats can't give, once the memory
layer is real.

## Target user (one wedge, not "everyone")
- **Primary, and the only one we build for first:** homeschool parents who already use
  AI for lessons and keep losing continuity between sessions. This is Robin's own
  situation, which makes it the cheapest to validate.
- Parents of kids in traditional school needing supplemental help are a later
  expansion, not a launch audience. "Flexible across any K-12 subject" is a trap that
  puts us against every competitor at once. Nail one subject or one workflow first
  (whichever Robin and Arowyn hit most), then widen.

## Core workflow (the validated part)
- Parent or student pastes an assignment description, study guide, test outline,
  worksheet, or topic request. Optional PDF/image upload of worksheets and rubrics for
  precise alignment.
- The tutor generates parent-ready output:
  - Study notes and summary sheets tuned to the child's grade and learning style.
  - Practice tests and quizzes with **answer keys on a separate page**.
  - Topic explanations at an age-appropriate level, with checkable sources.
  - Lesson outlines, project ideas, teaching guidance for a chosen method (creative
    writing techniques, Socratic history, step-by-step math).
- Output is clean and ready to print or share with no editing.

## Trust and accuracy (first-class, not a footnote)
This serves anxious parents teaching real children, so a confident wrong answer is a
liability and a churn driver.
- Factual content in explanations and research dives must cite checkable sources.
- Answer keys stay on a separate page so a kid can't see them by accident.
- Age-appropriateness is enforced in the prompt and reviewable by the parent.
- Flag low-confidence claims rather than asserting them.

## Where it's built: the MemoirQuill platform
This is the tutoring sibling in the **Quill family**. MemoirQuill is the rebrand of
Oriva (`~/Code/novadiem/oriva`, memoirquill.com registered, v1 built and in dogfood).
The synergy is a shared brand and a shared, already-built technical platform, not the
forced "learning sessions become memoir chapters" pitch.

MemoirQuill already has the plumbing this product needs, built and tested:
- **Document ingestion + normalization** of messy imports (`SessionDocument`,
  `validateSessionDocument`). Reuse for assignment / study-guide / worksheet uploads.
- **A resumable multi-stage LLM pipeline** (`run-pipeline.ts`) with per-stage model
  routing via OpenRouter. Reuse for the generation chain.
- **pgvector retrieval** (`retrieval.ts`: `embedText` / `storeFragmentEmbedding` /
  `findSimilarFragments`). This is the real vector layer the v2 mastery model needs,
  already working. The unbuilt Rheo memory tracks are not the only path.
- **Provenance + safety/coverage gates** on generated prose. Directly relevant to the
  trust/accuracy section above.
- **Consent + billing gate**, deletion and export flows. Reuse for a paid parent
  product holding a child's data.

Stack: Next.js + Prisma + Postgres/pgvector + pg-boss worker. That is a more natural
home for a parent-facing web product with printable output than the Telegram-bot Rheo
runtime.

**Decision to make:** build the tutor as a sibling app on the MemoirQuill platform
(recommended) vs. a Rheo mode. Rheo's layered-memory model stays the conceptual frame
for per-child mastery state, but storage and retrieval lean on Oriva's Postgres +
pgvector, which exists today.

## Build order: v1 ships on what exists, v2 is the upgrade

### v1 — generation engine + thin per-child profile (build now)
No mastery graph and no vector retrieval needed yet.
- The per-child profile is a plain note (markdown/JSON or a small Prisma table): grade,
  subjects, learning-style notes ("responds to visual examples and short practice
  sets"), and current weak spots. Edited by hand or appended after a session.
- This tests the whole core hypothesis (does structured generation plus a light profile
  beat ad-hoc chats?) with almost no new infrastructure. Ingestion, the pipeline, and
  output formatting are reused from MemoirQuill. Only the tutoring prompts and the
  profile are genuinely new.

### v2 — semantic mastery model (the sellable upgrade, not the blocker)
- **Episodic:** session digests of what was covered, performance, and outcomes.
- **Semantic graph:** mastery model of concepts with mastery levels, difficulty
  history, prerequisite links, and upcoming-test priorities.
- **Procedural:** what teaching patterns work for this specific child.
- Retrieval uses MemoirQuill's existing pgvector service, not the unbuilt Rheo SQLite
  tracks. The mastery model itself (concepts, levels, prerequisites) is the genuinely
  new build; the vector plumbing under it already exists.
- Agent retrieves relevant history at session start and updates the model at session
  end. Enables real spaced repetition and targeted review.

Do not gate the product on v2. It is the moat we add once v1 is proven, not the
foundation itself.

## Validation before code (given the cash-flow stretch)
The hypothesis can be tested for nearly nothing:
1. Keep tutoring Arowyn with a structured per-child profile and the v1 output formats.
2. Compare against the current ad-hoc Claude chats. Does the structure actually win?
3. Only commit a framework run to v1 once that answer is yes.

## Suggested next steps
1. Write the per-child profile format and the v1 output templates (notes, quiz +
   separate answer key, sourced explanation).
2. Dogfood with Arowyn's real assignments for two to three weeks.
3. If it beats ad-hoc, promote to a framework run as a MemoirQuill-sibling app,
   reusing ingestion + pipeline + model routing.
4. Add v2 (mastery model on the existing pgvector layer) only after v1 is proven.

## Open questions
- Which single subject or workflow is the launch wedge?
- One codebase or two? Tutor as a mode inside the MemoirQuill app, a separate app on
  the same platform, or a standalone product. Standalone needs its own acquisition
  story against crowded competitors.
- Pricing and who pays (parent subscription, one-time, free dogfood only?), and whether
  it shares MemoirQuill's billing/consent gate.
- Branding within the Quill family: which working name, and how the two products
  cross-sell.
