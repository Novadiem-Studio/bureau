---
priority: 06
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: external-notary-review
---

# 06. External notary review (The Notary)

## One-liner
Let a running framework workflow cue **The Notary** — an external cold reviewer that reads only
explicitly allowed artifacts from a sealed packet, attests what it read, and writes a bounded
review artifact back into the run without Robin copy-pasting context between sessions.

## Problem
The framework gets value from cold review — The Challenger sees artifacts, not the conversation
that produced them. But Robin sometimes wants an extra outside sanity check while a run is paused,
especially around workflow shape, hidden implementation risks, and mechanical oversights. Today
that requires manually copying artifacts into Codex and copying findings back. That works, but
it breaks flow. The Notary should wait for an explicit cue, read the right artifacts, and place
its review in the run directory, while preserving the same coldness discipline that makes The
Challenger useful.

## Idea
1. Define an `external-review.json` cue packet with question, cold-read allowlist, denied files,
   and `write_to` path. `state.json` may hold only a short `external_review` status/path pointer.
2. The framework writes the cue at checkpoints or sensitive design calls where an outside view adds value.
3. The Notary reads only the named artifacts — never `log.md`, `state.json` decisions, or prior
   Challenger findings — and writes one bounded `RUN_DIR/reviews/notary-review.md`.
4. The Conductor reads that artifact and adjudicates (accept / reject / route through normal
   adjudication) — same process as an official Challenger finding, labeled as advisory/notary.
5. Ministry of Flow surfaces runs with pending `external_review.status = requested` and links to the artifact.
6. Robin remains responsible for Visionary approval.

## Guardrails
**Core principle:** The Notary is artifact-cold by default. It must not read the narrative record
of how a decision was reached.

Default allowed inputs: `spec.md`, `plan.md`, `prompts.md`, relevant code/diff, explicit repro
artifact, workflow files and conventions when the question is about workflow shape,
`model-routing.json` only when the cue explicitly asks about routing.

Default denied inputs: `log.md`, `state.json` decisions, Conductor commentary, prior agent
rationale, Visionary back-and-forth, previous Challenger findings (unless the cue explicitly asks
for a second-pass follow-up).

**The Notary may:**
- Read the allowlisted artifacts.
- Inspect named code/diffs.
- Write one review artifact to the `write_to` path.
- Identify missing artifacts needed for valid cold review.
- Recommend a hand-back prompt or a correction.
- Attach a coldness receipt (hashes of what was read, matched against the cue).

**The Notary may NOT:**
- Approve Visionary checkpoints.
- Merge, push, deploy, or alter production boundaries.
- Edit source files or workflow artifacts directly.
- Read denied inputs to become "more helpful."
- Silently expand scope.
- Replace the official in-framework Challenger.

## Proposed cue contract

In `RUN_DIR/external-review.json`:
```json
{
  "external_review": {
    "requested": true,
    "role": "notary",
    "cold": true,
    "question": "Does the proposed bug-fix workflow stay lean, parse cleanly, and preserve cold review?",
    "read": ["spec.md", "docs/conventions.md", "workflows/index.md"],
    "do_not_read": ["log.md", "state.json"],
    "write_to": "reviews/notary-review.md",
    "status": "requested"
  }
}
```

The review artifact (`RUN_DIR/reviews/notary-review.md`) declares its inputs: what it read, what
it did not read, the question, verdict, findings, coldness receipt, and suggested hand-back.

## Likely home
`templates/external-review.json` cue packet + short `state.json` pointer + `notary-review.md`
artifact convention + `agents/notary.md` + Conductor instructions for consuming it + selected
workflow hookpoints + Ministry of Flow surface. Build via `feature` workflow.

## Done when
On a design-call pause, the framework writes a cue; The Notary reads only the named artifacts
and writes `notary-review.md`; the Conductor consumes it without Robin moving text by hand;
Ministry of Flow shows the cue status. On a future run like `bug-fix-workflow`, the framework
can pause at a design call and request a cold external notary review of workflow shape.

## Open questions
- Which fields belong in `external-review.json` vs. the short `state.json` pointer?
- Should review artifacts live at `RUN_DIR/reviews/notary-review.md` or reuse root-level `review.md`?
- Can external thread tools safely create a review thread with only artifact allowlists?
- How should the system prove the reviewer did not read denied files?
- Should Notary reviews count in future Tally accounting as Challenger-like review passes?
- Which workflows are allowed to request this automatically vs. which require Robin to cue it?

## Non-goals
- Replacing The Challenger.
- Replacing Robin at checkpoints.
- Giving any external reviewer unattended write/merge/deploy authority.
- Letting The Notary read the run log by default.
- Creating a general chat bridge between agents.
- Making Ministry of Flow an agent orchestrator in v1.
