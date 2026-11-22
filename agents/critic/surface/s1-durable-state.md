# S1 — Durable state

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together.

## Your surface

A DB migration or schema change; a write to a persisted record, ledger row, or stored document; a
change to how persisted data is serialized, keyed, or de-duplicated.

Ask the slice's question of this surface only: what here corrupts persisted data without
announcing it? A write that fails loudly (an exception the caller surfaces, a migration that will
not run, a constraint error) is self-announcing; leave it out.

## Silent patterns to hunt

- A migration that rewrites or backfills existing rows through a default, truncation, or type cast
  that loses data, and still runs green on an empty test database.
- Two related records written outside one transaction, so a failure between them leaves one
  written and the other not.
- A changed serialization (a renamed field or enum value, a new date or number format) that old
  rows or other readers still parse the old way, falling back to a default instead of erroring.
- A de-duplication or natural key that changed, so existing rows stop matching: duplicates get
  inserted, or distinct records collapse onto one.
- An upsert or replace that overwrites fields the caller did not supply with null or a default.
- A failed write whose error is swallowed (catch-and-log, an ignored return code, an error forced
  to success), so the caller reports success with nothing persisted.
- A delete or cascade on local persisted rows that now removes more than intended: a widened
  filter, a new cascade. A delete sent to an external system is S4.
- A file replaced in place instead of written to a temp path and renamed, so an interruption
  leaves it truncated.

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.
If that other surface is in `fired`, its own lens owns it: put it in neither list. `gate_miss`
names only surfaces outside `fired`.

For example, a wrong amount in a stored ledger row belongs to S2, and two writers racing on the
same row to S5. How a fired pair combines is the interaction reviewer's; stay on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no transaction, constraint, or error check) anchors to the line where the guard
  belongs.
- The failure scenario names the concrete input and the wrong outcome: which row, value, or call,
  and what ends up persisted wrong.
