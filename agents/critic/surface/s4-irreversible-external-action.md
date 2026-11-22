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
- A retry or redelivery that repeats the action with no idempotency key or sent marker, so the
  recipient gets it twice. This surface is the one home for a non-idempotent retry; two workers
  firing at the same moment is S5.
- A send, delete, or deploy reachable from a test, dry-run, or dev path because its guard flag
  defaults on or is read from the wrong environment.
- A recipient, host, or resource id taken from unvalidated input or the wrong variable, so the
  action lands on the wrong party or resource.
- A batch against an external system whose filter widened: a remote delete or a notify now
  covers far more targets than intended. A delete of local persisted rows is S1.
- A destructive call that lost the confirmation, soft-delete, or dry-run step the old code had.
- A failed external call swallowed while local state is marked done, so the system records a send
  that never happened (or misses one that did).

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.
If that other surface is in `fired`, its own lens owns it: put it in neither list. `gate_miss`
names only surfaces outside `fired`.

For example, a record left half-written by the rollback belongs to S1, and two workers firing the
same action at once to S5. How a fired pair combines is the interaction reviewer's; stay on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no idempotency key, no environment check, no confirmation) anchors to the line
  where the guard belongs, usually just before the call that fires.
- The failure scenario names the concrete input and the wrong outcome: which event or retry, and
  what reaches which external party.
