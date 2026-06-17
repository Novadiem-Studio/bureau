# External-action boundary

This document is the canonical taxonomy of external actions that require a human gate before
an agent fires them. The default rule applies whenever an action's classification is uncertain.
This boundary is parallel to the production-deploy boundary defined in `agents/orchestrator.md`
— it is not a subset of it and does not replace it.

---

## External-action taxonomy

An external action is any agent-initiated action that produces a side effect outside the local
process — one that reaches a real recipient, external system, or third-party service.

- **Email and SMS sends** — any outbound message to a real recipient address or phone number
- **Chat platform posts** — Slack, Discord, Teams, or equivalent outbound posts
- **Webhook calls to external URLs** — any POST/PUT/PATCH to a non-local URL that produces a side effect on the receiving system
- **Customer-facing notifications** — push notifications, in-app notifications, or equivalent outbound alerts to real end users
- **Payment triggers** — charge initiation, refund, or subscription modification
- **Calendar invites or event mutations** — any calendar event visible to or delivered to external participants
- **DNS and infrastructure mutations** — DNS record changes, domain transfers, firewall rule changes, or equivalent provider-side changes
- **Any other outbound HTTP to a non-local URL with a side effect** — the catch-all for actions not enumerated above but that produce an externally visible effect

> **RECIPROCAL SYNC NOTE:** `agents/critic.md` holds a duplicate of this 8-category taxonomy,
> inlined there because the cold Challenger cannot read this doc at review time (per the input
> contract in `docs/conventions.md`). If the taxonomy is edited here, it must also be edited in
> `agents/critic.md`. The canonical source is always this file; if the two copies ever differ,
> correct `agents/critic.md` to match — never the reverse.

---

## Default rule

> **When unsure whether an action is external, treat it as external and gate it.**
>
> This is not a tie-breaker heuristic — it is the primary rule. Ambiguity resolves toward
> caution. An action whose type or target cannot be confirmed from written context must be
> treated as external and held at the gate until a human decides.

---

## Reversibility

External actions fall into exactly two tiers. There is no intermediate "staged" tier.

**`irreversible`** — once fired, the Bureau cannot undo or recall it: a sent SMS or email, a
webhook that already triggered a charge, a payment initiated, a DNS record changed, a calendar
invite delivered to external participants.

**`reversible`** — undoable by a later deliberate action: a posted Slack message (deletable),
a created-but-cancellable calendar event, a saved-but-unsent draft email (delete the draft),
a webhook payload assembled but not yet POSTed.

**`irreversible` is the default tier when the classifier cannot decide.**

**Cold-agent classification question** — apply this verbatim before classifying:

> Ask: once I fire this, can the Bureau itself undo it?
> If no → irreversible.
> If yes, by a later deliberate action → reversible.
> When you cannot decide, classify irreversible and gate it.

**Important:** `reversible` does not mean free or invisible. The human still decides at the
same single gate. The tier only tells the human that the blast radius is recoverable — not
that the action is safe to skip the gate.

---

## Relationship to the production-deploy boundary

The external-action boundary and the production-deploy boundary (defined in
`agents/orchestrator.md`) are parallel protections for different risk classes — neither
subsumes the other, and neither replaces the other. The production boundary protects against
deploy-surface changes (promoting a release, shipping beyond dev, pushing to a public
environment); the external-action boundary protects against outbound communications and
externally visible side effects. An action can trigger one boundary, both, or neither — they
are evaluated independently.

---

## Limitations (v1)

v1 enforcement is text-based and Challenger-verified — there is no runtime interceptor. An
agent that ignores the gate can still fire an external action; the framework cannot
technically prevent it. The Challenger cold-check (Review 1 and Review 2) is the second
layer of enforcement, and the Conductor's log-before-firing discipline is the operational
record. This section exists so a maintainer does not mistake the written gate for a hard
technical block.
