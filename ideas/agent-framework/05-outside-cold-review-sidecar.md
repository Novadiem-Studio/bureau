---
priority: bundle-05
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: outside-cold-review-sidecar
source-ideas:
  - source-notes/06-codex-outside-challenger-sidecar.md
---

# 05. Outside cold review sidecar

## Purpose

Add an optional advisory Codex review path that preserves coldness: the reviewer reads only an
explicit allowlist, writes one bounded artifact, and never replaces The Challenger or the
Visionary checkpoint.

## Why this is later

The idea is valuable, but it touches artifact boundaries, thread coordination, Ministry of
Flow visibility, and proof-of-coldness questions. It should come after the framework has clear
preflight, regression, close-out, and accounting artifacts.

## First implementation slice

Do not automate thread creation in v1. Start with the artifact contract:

1. Add an `external_review` block to `templates/state.json` or define a separate
   `external-review.json` convention.
2. Define `RUN_DIR/reviews/outside-challenger.md` as the default write path.
3. Add `docs/outside-cold-review.md` with:
   - allowed inputs;
   - denied inputs;
   - review artifact format;
   - Conductor adjudication rules;
   - advisory status.
4. Add Conductor instructions for consuming the artifact:
   accept, reject, route through normal adjudication, or checkpoint.
5. Add a manual cue flow before any automation:
   the Conductor writes the cue, Robin or Codex opens only the allowlisted artifacts, and the
   sidecar writes the review artifact.

## Automation slice

Only after the manual flow works:

- use Codex app thread tools to create a review thread with the allowlisted artifact list;
- surface pending cues in Ministry of Flow;
- count sidecar reviews in accounting as advisory review passes;
- add a coldness receipt to the review artifact.

## Done when

- A run can request an outside review without copying freeform chat context.
- The sidecar declares exactly what it read and did not read.
- The Conductor consumes the sidecar review as advisory, not authoritative.
- The reviewer cannot silently expand scope or approve checkpoints.

## Risks

- The sidecar can accidentally become a same-context reviewer if it reads `log.md`,
  `state.json` decisions, prior Challenger findings, or Conductor rationale.
- Automation before the artifact boundary is proven will create trust problems.
- This must not become a general chat bridge between agents.

