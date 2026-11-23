# S3 — Auth / access / privacy

S-id and name mirror `workflows/build-review-cold.md` step 3; edit both together.

## Your surface

A change to who can read or write what: an authz check, a permission or role gate, a visibility or
scoping filter, a tenancy boundary, or a secret/PII path.

Ask the slice's question of this surface only: what here leaks access or data without announcing
it? A user wrongly locked out sees an error and reports it; that is self-announcing, so leave it
out. A user wrongly let in sees nothing unusual.

## Silent patterns to hunt

- A list query or endpoint that drops or widens its owner or tenant filter, returning other
  people's records with no error.
- An authz check on the read path but not the write path, or on the UI route but not the API it
  calls.
- A record fetched by an id from the request with no ownership check.
- A check that fails open: default allow, a missing role treated as privileged, an exception in the
  check caught and treated as authorized.
- A secret, token, or PII value written to a log, error message, analytics event, URL query
  string, or response field.
- A cache keyed without the user or tenant, so one person's response is served to another.
- A new entry point (admin tool, script, webhook handler, background job) that reaches the data
  without the normal gate.
- A visibility state (private, draft, deleted) that a new reader, search index, or export ignores.

## Out of lens

out of lens: a risk on another surface goes in `gate_miss`, never in `findings`.
If that other surface is in `fired`, its own lens owns it: put it in neither list. `gate_miss`
names only surfaces outside `fired`.
So it is not lost, add one line under `### Warnings` in your `.md`: start it `partner <S-id>:`
in place of a finding id, then its `file:line`. The note is for the Conductor; it is never
handed to another reviewer.

For example, how a leaked record got persisted belongs to S1, and a message sent to the wrong
person to S4. How a fired pair combines is the interaction reviewer's; stay on yours.

## Anchoring

- `line` is in the post-change file.
- A missing guard (no ownership check, no scope filter, no redaction) anchors to the line where the
  guard belongs.
- The failure scenario names the concrete input and the wrong outcome: which user or tenant asks
  for what, and whose data or permission they get.
