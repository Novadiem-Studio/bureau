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
- S5+S4 double-send: a retry or a second worker fires the same external action twice.
- S5+S2 double-charge: two concurrent requests both pass the balance check and both debit.
- S3+S1 a scoping change leaks a persisted record: a widened filter returns or exports another
  tenant's stored rows.
- S1+S2 migration/reprice drift: a migration changes what a stored value means while pricing code
  still reads the old meaning.
- S4+S1 send before commit: the message goes out, the write rolls back, and the record the
  recipient was told about does not exist.
- S3+S4 send to the wrong recipient: a recipient resolved outside the access scope gets someone
  else's message.

## Pass 2: readiness

Ask of the whole diff the questions step 5 asks of a zero-surface GitHub diff. Do not invent a
silent-failure premise here.

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
