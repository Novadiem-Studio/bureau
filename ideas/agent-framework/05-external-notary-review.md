---
priority: bundle-05
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: external-notary-review
source-ideas:
  - source-notes/06-external-notary-review.md
---

# 05. External notary review (The Notary)

## Purpose

Add an optional advisory **external notary review** path that preserves coldness: **The Notary**
reads only an explicit allowlist (a sealed packet), attests what was read with a hash receipt,
writes one bounded review artifact, and never replaces The Challenger or the Visionary
checkpoint.

The Notary is a **utility spawn** (like Tally and Scoot), not a tarot cast member — invoked on
demand, provider-neutral (Codex one-shot, Claude packet, etc.). Challenger hunts flaws inside
the run's artifact discipline; The Notary witnesses boundaries — this review saw exactly this,
and nothing else.

## Why this is later

The idea is valuable, but it touches artifact boundaries, thread coordination, Ministry of
Flow visibility, and proof-of-coldness questions. It should come after the framework has clear
preflight, regression, close-out, planning-quality, and accounting artifacts. Bundle 03 should
land first so the reviewed specs already name their outcome; Bundle 04 should land first
because both bundles touch `templates/state.json` and `agents/orchestrator.md`.

## What we now know (2026-06-20 — after the delegate work + Codex review)

Six reviews of the delegate (Bundle 09) and a repo-grounded Codex pass surfaced things that change
this design. Where this conflicts with the slices below, this wins.

- **Coldness is isolation, not a promise.** The contract below relies on The Notary *declaring*
  what it read and a prompt *asking* it to stay in bounds. That can't prove coldness — a reviewer
  with workspace or memory access (a Codex thread, say) can read denied files and still attest it
  didn't. The strong form: feed The Notary an **isolated, hash-pinned packet** of only the
  allowlisted files, run with **no workspace access**, so reading out of scope is impossible rather
  than discouraged. v1 (manual) can't fully isolate, so v1 coldness is best-effort + a hash receipt;
  true coldness arrives when The Notary is a **headless one-shot fed only the packet** — which is
  also cheaper than a live thread (the Bundle 09 token finding: the cost was driving a live session,
  not reading files).
- **Cue vs receipt — contradiction fixed.** The cue packet (`external-review.json`) holds the
  allowlist, denylist, and the **intended-artifact hashes**. The **coldness receipt** lives with the
  *review artifact* (what was actually read, with hashes) and must **match the cue** — closing the
  "Conductor sent X, Notary read Y" gap. (An earlier draft put the receipt in both places; it
  belongs with the review, and the cue carries the hashes it is checked against.)
- **Fit the existing cold-review convention, don't invent one.** The framework already has a cold
  code-review layout (root-level `review-target.md` + `review.md`, `workflows/code-review.md`) and a
  canonical persona input/consumption receipt format (`docs/conventions.md`). Reuse those rather
  than a bespoke `RUN_DIR/reviews/` path; reconcile the exact paths in the run.
- **Request IDs + versioned artifacts.** A single cue/output path overwrites history on a retry or a
  second requested review. Each cue and review carries a request ID; retries version, never overwrite.
- **Provider-neutral reviewer.** "Codex" in the source note is one option, not a requirement —
  routing is provider-neutral (`config/runtimes/`). What makes a review cold is the **packet + no
  workspace access**, not which model runs it. A headless Claude one-shot fed only the packet is
  cold, cheap, and controllable.
- **Considered and rejected:** a Notary rate-limit / circuit-breaker (proposed in review) is
  machinery the over-engineering test would flag on a manual-first advisory reviewer with no
  demonstrated failure requiring it. Don't add it.

### Relationship to the delegate (09)

The delegate work clarified where The Notary sits. They are complements on the coldness axis:
**The Notary is the cold *artifact* reviewer** (strict packet, advisory only); **the delegate is
the warm *process* reviewer** that reads `log.md` to judge how the Conductor handled the
Challenger. The delegate (or Conductor) can **request a Notary review** for a high-stakes
artifact and reference it by path in its decision ledger (provenance). And the delegate's
**self-audit gate** can *use* The Notary as the cold auditor that samples `proceed` verdicts —
so 05's packet contract also serves 09. Neither blocks the other.

## First implementation slice

Do not automate thread creation in v1. Start with the artifact contract:

1. Define `templates/external-review.json` as the packet template, and add only a short
   `external_review` status/path pointer to `templates/state.json`, not the full packet.
2. Define `RUN_DIR/external-review.json` as the cue packet and
   `RUN_DIR/reviews/notary-review.md` as the default review artifact path (`role: notary` in the
   cue).
3. Add `docs/notary-review.md` with:
   - allowed inputs;
   - denied inputs;
   - memory access denied by default, with explicit memory excerpts allowed only when
     allowlisted with provenance;
   - review artifact format (including coldness receipt);
   - Conductor adjudication rules;
   - advisory status.
4. Add `agents/notary.md` — persona, attestation rules, receipt format.
5. Add Conductor instructions for consuming the artifact:
   accept, reject, route through normal adjudication, or checkpoint.
6. Add a manual cue flow before any automation:
   the Conductor writes the cue, Robin or an external runtime opens only the allowlisted
   artifacts, and The Notary writes the review artifact.

## Automation slice

Only after the manual flow works:

- use external thread tools to create a review thread with the allowlisted artifact list;
- surface pending cues in Ministry of Flow;
- count Notary reviews in accounting as advisory review passes;
- add a coldness receipt to the review artifact.

## Done when

- A run can request an external notary review without copying freeform chat context.
- Any `state.json` external-review addition is only a short status/path pointer; the allowlist,
  denylist, and intended-artifact hashes live in `external-review.json` (the cue), and the coldness
  receipt — actual files read, with hashes that match the cue — lives with the review artifact.
- Memory is denied by default; any memory excerpt supplied to The Notary is explicit,
  allowlisted, and provenance-bearing.
- The Notary declares exactly what it read and did not read — and, in the strong form, is fed an
  isolated packet with no workspace access, so it *cannot* read outside scope (declaration is the
  v1 best-effort fallback, isolation is the real guarantee).
- The Conductor consumes the Notary review as advisory, not authoritative.
- The reviewer cannot silently expand scope or approve checkpoints.

## Risks

- The Notary can accidentally become a same-context reviewer if it reads `log.md`,
  `state.json` decisions, prior Challenger findings, or Conductor rationale.
- Automation before the artifact boundary is proven will create trust problems.
- This must not become a general chat bridge between agents.
