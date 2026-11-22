# S5 — Concurrency / race

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together.

## Your surface

A diff that adds or changes concurrent access, shared mutable state, ordering assumptions, or a
non-atomic read-modify-write on durable or shared data, where the failure is a lost update,
double-processing (double-charge, duplicate send), or a dropped or reordered event. Cue: new
locks, transactions, or async ordering, or a shared-state write with no atomicity or idempotency
guard on a durable or money surface.

Ask the slice's question of this surface only: what here goes wrong only when two things run at
once, without announcing it? Single-threaded tests rarely reach these paths.

## Silent patterns to hunt

- A read-modify-write on a counter, balance, or document with no lock, compare-and-swap, or atomic
  update, so concurrent writers lose updates.
- Check-then-act: an existence or limit check followed by a separate insert or deduction, with
  nothing stopping two callers from both passing the check.
- A job, queue consumer, or webhook handler that is not idempotent under redelivery, so an
  at-least-once message is processed twice.
- A lock that is not exclusive on every platform it runs on, is released in the wrong scope, or is
  not released on the error path.
- An ordering assumption broken by the change (a removed await, a reordered callback, parallel
  dispatch), so a later event can apply before an earlier one.
- Shared module-level or global mutable state used across requests, threads, or workers.
- A transaction isolation level too weak for the invariant it is meant to protect.
- A file or record written in place while another process can read it mid-write.

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.

A wrong amount computed by one caller alone is S2; an action that fires before commit with no race
involved is S4. When the other fired surface is involved, the interaction reviewer hunts how the
two combine; stay on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no lock, no atomic update, no idempotency key) anchors to the line where the
  guard belongs, usually the read or the check that starts the window.
- The failure scenario names the concrete interleaving and the wrong outcome: which two callers,
  in which order, and what update is lost or doubled.
