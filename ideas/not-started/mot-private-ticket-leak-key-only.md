# M.O.T.: private ticket leaks into API-key-only ticket list

**Priority:** high — real privacy exposure, not a cosmetic test failure. A private ticket is
visible to an API-key-only caller that should not see it.
**Scope:** `mot/` web app only (the private-route gating on the tickets list + single-ticket
read). Backend/data + route layer.

## Context — why do this

Surfaced (not caused) by the Rheo Memory Track 3 run (`20260622-rheo-memory-track3`). The
integration gate's full `npm test` showed one red: `tests/integration/private-routes.test.ts`
→ **AC-PRIVATE**. The Conductor and Robin each independently reproduced it failing **identically
at base `main` (`e9d7311`)** before any Track-3 work, so it is **pre-existing and unrelated to
Track 3** — but it is a genuine bug already sitting red on `main`.

The test asserts that a caller authenticated with the API key only (no session) must NOT see a
private ticket in `GET /tickets`, and must get a 404 (not 403) on `GET /tickets/:id` for that
private ticket. The list assertion fails: the private ticket's id IS present in the key-only
list response. So **private tickets are exposed to key-only callers** in MOT today.

This matters: MOT holds life-admin tickets, some explicitly marked private. A key-only caller
(any integration holding the MCP/API key, not a logged-in session) being able to enumerate
private tickets is a real confidentiality leak, not a flaky test.

## What to do (MVP)

1. Locate the tickets list query/handler and the single-ticket read; find where the
   private/visibility predicate is applied (or missing) for key-only auth vs session auth.
2. Make the list exclude private tickets for key-only callers, and make the single-ticket read
   return 404 (not 403) for a private ticket a key-only caller may not see — matching the test's
   existing assertions.
3. Confirm session-authenticated callers still see their private tickets (don't over-correct).
4. Green `tests/integration/private-routes.test.ts` (AC-PRIVATE) and the full suite; add a case
   if the existing coverage doesn't pin the session-vs-key distinction.

## Out of scope
- Any redesign of the auth model. This is a gating fix on existing routes, within the current
  Next.js / better-sqlite3 stack.

## Workflow
`bug-fix` — the failing test is the repro; fix the gate, re-run, stop at dev.
