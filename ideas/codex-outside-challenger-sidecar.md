# Idea Definition - Codex Outside Challenger Sidecar

> **Status:** idea (pre-spec)  
> **Suggested workflow:** `feature`  
> **Suggested run slug:** `codex-outside-challenger-sidecar`  
> **Mode:** existing project (framework + Ministry of Flow (aka Logistics)/watch process integration)  
> **Author:** Robin (Visionary), captured by Codex 2026-06-15  
> **For:** The Conductor -> Analizer 2000 -> The Architect -> ... (feature pipeline)

---

## One-liner

Let a running framework workflow cue a **Codex outside challenger** that waits on the side,
reads only explicitly allowed cold artifacts, and writes a bounded review artifact back into the
run without Robin copy-pasting context between sessions.

---

## Problem

The framework already gets value from cold review: The Challenger sees the artifacts, not the
conversation that produced them. But Robin sometimes wants an extra Codex sanity check while a
run is paused, especially around workflow shape, hidden implementation risks, and mechanical
oversights.

Today that extra review requires manual copying:

- Robin notices the checkpoint.
- Robin opens or pastes the relevant run files into Codex.
- Codex reviews them.
- Robin copies the feedback back to the framework session.

That works, but it breaks the flow. The outside reviewer should be able to wait for an explicit
cue, read the right artifacts, and place its review in the run directory, while preserving the
same coldness discipline that makes The Challenger useful.

---

## Core Principle

The outside challenger is **artifact-cold by default**.

It should not read the narrative record of how the decision was reached. It should judge the
artifact as another competent reviewer would encounter it.

Default allowed inputs:

- `spec.md`
- `plan.md`
- `prompts.md`
- relevant code or diff
- explicit repro artifact for `bug-fix` runs, e.g. `repro.md` / `bug-fix-repro.md`
- workflow files and conventions when the question is about workflow shape
- `model-routing.json` only when the cue explicitly asks about routing or tier fit

Default denied inputs:

- `log.md`
- `state.json.decisions`
- Conductor commentary
- prior agent rationale
- Visionary back-and-forth
- previous Challenger findings, unless the cue explicitly asks for a second-pass follow-up

Important distinction: a **watcher/dispatcher** may inspect cue metadata in `state.json` to know
that a review is requested. The **reviewer context** should receive only the cue text and the
artifact allowlist, not the run log or hidden decision trail.

---

## Proposed Cue Contract

The framework can expose an external-review request in `state.json`, while keeping the reviewer's
inputs explicit:

```json
{
  "external_review": {
    "requested": true,
    "role": "codex_outside_challenger",
    "cold": true,
    "question": "Does the proposed bug-fix workflow stay lean, parse cleanly, and preserve cold review?",
    "read": [
      "spec.md",
      "docs/conventions.md",
      "workflows/index.md"
    ],
    "do_not_read": [
      "log.md",
      "state.json"
    ],
    "write_to": "outside-challenger.md",
    "status": "requested"
  }
}
```

The cue should be concrete enough that the sidecar does not have to infer the task from the run
history.

---

## Review Artifact

The sidecar writes one bounded artifact, for example:

```markdown
# Outside Challenger Review

Cold review: yes
Read: spec.md, docs/conventions.md, workflows/index.md
Did not read: log.md, state.json
Question: Does the proposed bug-fix workflow stay lean, parse cleanly, and preserve cold review?

## Verdict

Proceed with one correction.

## Findings

1. ...

## Suggested Hand-back

...
```

The artifact should declare its inputs so The Conductor can understand what kind of judgment it
is receiving.

---

## Workflow Integration

The outside challenger is not a replacement for the official Challenger. It is an optional extra
lane for cases where Robin wants a second angle without becoming a copy-paste bridge.

Possible flow:

1. The Conductor reaches a checkpoint or sensitive design call.
2. The workflow writes an `external_review` cue with an artifact allowlist and a question.
3. Ministry of Flow (aka Logistics), a local watcher, or a Codex thread bridge notices the cue.
4. Codex reads only the named artifacts.
5. Codex writes `RUN_DIR/outside-challenger.md`.
6. The Conductor reads that artifact and either accepts, rejects, or routes the finding through
   the normal adjudication process.
7. Robin remains responsible for Visionary approval.

This should be available at checkpoints, before Challenger spends an expensive pass, or before a
human "go" when the question is narrow and reviewable.

---

## Boundaries

The sidecar may:

- read the artifact allowlist named by the cue
- inspect code/diffs named by the cue
- write one review artifact to the named `write_to` path
- identify missing artifacts required for a valid cold review
- recommend a hand-back prompt or a correction

The sidecar may not:

- approve Visionary checkpoints
- merge, push, deploy, or alter production boundaries
- edit source files or workflow artifacts directly
- read denied inputs to become "more helpful"
- silently expand scope beyond the cue
- replace the official in-framework Challenger

The outside challenger is advisory. The Conductor still adjudicates; Robin still decides product
and direction calls.

---

## Ministry of Flow (aka Logistics) Surface

Ministry of Flow (aka Logistics) could make this feel natural:

- show runs with pending `external_review.status = requested`
- display the cue question and the allowlisted artifacts
- provide a "Run Codex outside challenger" action when automation is not available
- show whether the review was cold and which files were read
- link directly to `outside-challenger.md`
- distinguish sidecar findings from official Challenger findings

Later, if Codex thread coordination is available, Ministry of Flow (aka Logistics) could create or wake a dedicated
Codex review thread and pass only the allowed artifacts.

---

## MVP

1. Define the `external_review` cue schema.
2. Add a convention for `outside-challenger.md` review artifacts.
3. Teach selected workflows when they may request this lane.
4. Add a small watcher or Ministry of Flow (aka Logistics) action that starts the Codex review with only the allowed
   inputs.
5. Add Conductor instructions for consuming the outside review without treating it as Visionary
   approval.
6. Trial it on workflow-definition runs before allowing it near product code.

---

## Open Questions

- Should the cue live in `state.json`, a separate `external-review.json`, or both?
- Should review artifacts live at `RUN_DIR/outside-challenger.md` or under
  `RUN_DIR/reviews/`?
- Can Codex app thread tools safely create a review thread with only artifact allowlists?
- How should the system prove the reviewer did not read denied files?
- Should sidecar reviews count in future Tally accounting as Challenger-like review passes?
- Which workflows are allowed to request this automatically, and which require Robin to cue it?

---

## Non-goals

- Replacing The Challenger.
- Replacing Robin at checkpoints.
- Giving Codex unattended write/merge/deploy authority.
- Letting the outside reviewer read the run log by default.
- Creating a general chat bridge between agents.
- Making Ministry of Flow (aka Logistics) an agent orchestrator in v1.

---

## First Good Outcome

On a future run like `bug-fix-workflow`, the framework can pause at a design call and request:

> Cold outside review: does this workflow stay lean and preserve cold Challenger inputs?

Codex reads only the named artifacts, writes `outside-challenger.md`, and the Conductor can use
that finding without Robin moving text by hand.

