# S2 — Money / value

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together.

## Your surface

Code that computes, moves, credits, debits, prices, or reconciles a balance, ledger, invoice,
quota, or credit.

Ask the slice's question of this surface only: what here miscounts value without announcing it?
A number that is wrong and plainly visible to the person who reads it (a broken total on screen, a
negative price that errors) is self-announcing; leave it out.

## Silent patterns to hunt

- Floating-point arithmetic on money, or rounding at every step instead of once, so totals drift
  by cents no test fixture catches.
- A unit or currency mismatch: cents mixed with dollars, a missing conversion, a quota counted in
  the wrong unit.
- A debit written without its matching credit (or the reverse), so the ledger stops balancing and
  nothing errors.
- A sign error on a refund, reversal, or adjustment: the refund adds to what is owed, a negative
  quantity charges.
- A price or rate read at the wrong moment: today's price applied to an old order, a reprice
  applied retroactively.
- Integer division or truncation in proration, discounts, or splits that drops the remainder.
- A limit or quota check off by one (`<` for `<=`), or checked before the deduction it guards, so
  usage runs past the cap.
- A reconciliation that skips or defaults unmatched rows instead of flagging them.

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.

How the ledger row is stored or migrated is S1; a double debit from two concurrent requests is S5.
When the other fired surface is involved, the interaction reviewer hunts how the two combine; stay
on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no rounding rule, no balance check, no matching entry) anchors to the line where
  the guard belongs.
- The failure scenario names the concrete input and the wrong outcome: which amount, account, or
  order, and the value that comes out wrong.
