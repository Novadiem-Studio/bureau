# Surface interaction

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together. The seed pairs
in Pass 1 are examples, not an exhaustive list.

You run after both lens reviewers, alone, over the two surfaces in `fired`. Run two passes, in
order, and put every finding from both into your one `interaction.json`.

## Pass 1: cross-surface failures

Hunt only failures that arise between the two fired surfaces: a failure that needs both, which
neither lens owns alone.

- Read this round's `merged.json` first. Never restate a single-surface finding already in it,
  reworded or not. If a lens found it, it is not yours.
- Every Pass 1 finding has `surface: "X"` and `interacts` naming both fired S-ids.
- Anchor on the post-change line where the two surfaces meet (the send that runs before the
  commit, the check two callers pass at once). A missing guard anchors where the guard belongs.
- A risk on a surface outside `fired` goes in `gate_miss`, never in `findings`.

Seed pairs:
- S5+S4 double-send: the guard S4 relies on (a sent marker or idempotency check) is itself a
  non-atomic check-then-set, so two workers both pass it and both send. Each lens sees a guard;
  the failure is that the guard races.
- S5+S2 double-charge: the balance check that guards a debit reads outside the lock or transaction
  the debit takes, so two concurrent requests both pass it and the account goes past its limit.
- S3+S1 a scoping change leaks a persisted record: a write stores the record without its owner or
  tenant field (the data is all there), and a read filter treats a missing owner as shared (the
  filter is unchanged), so the record leaks to every tenant.
- S1+S2 migration/reprice drift: a migration changes what a stored value means while pricing code
  still reads the old meaning.
- S4+S1 send before commit: the message goes out, the write rolls back, and the record the
  recipient was told about does not exist.
- S3+S4 send to the wrong recipient: a recipient resolved outside the access scope gets someone
  else's message.

## Pass 2: readiness

Ask of the whole diff the questions step 5 asks of a zero-surface GitHub diff. Do not invent a
silent-failure premise here. The slice's "self-announcing, leave it out" rule does not apply in
this pass: step 5 readiness covers visible correctness too.

- Never re-file a lens finding from `merged.json`, or a Pass 1 finding, as an `R` finding.
- A silent-failure risk on a surface outside `fired` goes in `gate_miss`, not in an `R` finding.

The questions:

- Correctness: logic errors and mishandled edge cases in the changed hunks.
- Scope: files or behavior the diff changes with no evident tie to its purpose.
- Tests: do the tests exercise the changed behavior, and would they fail if it broke?
- Risks: a risk the diff carries that nothing in it flags or guards.
- Rollback evidence: can the change be reverted cleanly, and does the diff show how (a down
  migration, a flag, a revert path)?

Readiness findings use `surface: "R"` and `interacts: []`. Their ids still use the `X` prefix.

## Closure

From round 2 on, you own the `X` and `R` ids in your `closure-x.json`. Close or re-raise each one
per the slice's closure duty and closure accounting.
