# S4 — Irreversible external action

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together.

## Your surface

Code that sends (email, SMS, webhook, notification), deletes, deploys, or mutates external infra
(DNS, billing) where the effect can't be pulled back.

Ask the slice's question of this surface only: what here fires the wrong external effect, or fires
it at the wrong time, without announcing it? Once it has fired, a later error does not undo it.

## Silent patterns to hunt

- An action fired before the local transaction commits, so a rollback leaves the external effect
  in place.
- A retry on timeout or error that repeats the action with no idempotency key or sent marker, so
  the recipient gets it twice.
- A send, delete, or deploy reachable from a test, dry-run, or dev path because its guard flag
  defaults on or is read from the wrong environment.
- A recipient, host, or resource id taken from unvalidated input or the wrong variable, so the
  action lands on the wrong party or resource.
- A batch whose filter widened: a delete or a notify now covers far more targets than intended.
- A destructive call that lost the confirmation, soft-delete, or dry-run step the old code had.
- A failed external call swallowed while local state is marked done, so the system records a send
  that never happened (or misses one that did).

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.

A record left half-written by the rollback is S1; two workers firing the same action at once is S5.
When the other fired surface is involved, the interaction reviewer hunts how the two combine; stay
on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no idempotency key, no environment check, no confirmation) anchors to the line
  where the guard belongs, usually just before the call that fires.
- The failure scenario names the concrete input and the wrong outcome: which event or retry, and
  what reaches which external party.
