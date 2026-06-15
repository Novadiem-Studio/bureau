# The Ministry System

A personal intelligence and operations government for Robin Goodwin, staffed by Tuttle.
Inspired by Orwell's 1984 and Gilliam's Brazil.

**Tone:** solemn Art Deco civic surface, absurd plumbing underneath, competent behavior
underneath that. Tongue-in-cheek labels; not dystopia cosplay on client-facing surfaces.

---

## Where this sits in the Novadiem stack

Three nested layers — same building, different names on different doors:

| Layer | Name | What it is | Where it lives |
|-------|------|------------|----------------|
| **Studio** | Novadiem Studio | Hireable studio brand; Sacred Instrument material language | novadiem.com, poster headers |
| **Civic shell** | The Ministries | Robin's ops government — this doc | M.O.T., M.O.I., domain ministries, `mot.novadiem.com` |
| **Secret order** | The Bureau | Inner lore for the multi-agent *build* framework | `LORE.md`, workshop cast, tarot, THE ENGINE |

**Poster rule (when canon updates):** THE HUB shows **The Ministries** (routing, records,
intake). THE ENGINE shows **the Bureau** at work in the workshop. Clients see studio;
operators see ministries; the cast stays esoteric.

**Do not merge cast ↔ ministries 1:1.** Ministries are faceless domains (see § Ministries vs
workers). Bureau specialists are workers who serve domains — especially **Ministry of Flow**
for builds — not mascots for Commerce or Plenty.

| Framework | Ministry overlap |
|-----------|------------------|
| **Archive** (per-run artifacts) | Same discipline as M.O.T. — nothing done until recorded |
| **Witness** (`output/studio/briefing.md`) | Studio-wide run digest; may feed M.O.I. later, not the same system |
| **Ministry of Flow / Logistics** (`~/Code/novadiem/society-desk`) | Read-only **run** kanban across framework installs — the Flow ministry console; not M.O.T. tickets |
| **Ministry of Flow** *(domain)* | Active builds, blocked pipeline — framework runs, Oriva, M.O.T., experiments |
| **Tuttle** | Primary civil servant — files and retrieves across all ministry domains |
| **Bureau cast** | Workers on build/flow work inside framework runs — not ministry mascots |
| **Robin** | **Minister** in this doc · **Visionary** in `LORE.md` — same person, different hat |

**Visual canon:** TVA × Art Deco × World's Fair Futurism + *Brazil* ducting — see
`VISUAL-CANON.md` § Workshop environment v1.5. Ministries are the bureaucracy those
tubes nominally serve.

---

## Ministries vs workers

**Ministries are domains, not people.** A ministry is a routing label, a ticket queue,
a department seal on the wall — Works, Commerce, Plenty, Peace, Education, Flow, Interior,
Foreign Affairs, plus the core pair M.O.T. and M.O.I. They have **no faces**, no character
art, no tarot card, no agent file. You do not spawn "the Ministry of Commerce."

**Workers get things done for the ministries.** They have faces, voices, spawn configs,
and responsibility. Work is filed *to* a ministry; work is performed *by* a worker.

| Kind | Examples | Serves |
|------|----------|--------|
| **Civil servant** | Tuttle | All ministries — intake, filing, retrieval, digests |
| **Bureau specialists** | Conductor, Mage, Analizer, Witness, … | **Ministry of Flow** (active builds) and framework runs; esoteric inner order |
| **Shop droids** | Tally, Scoot | Cheap read-only odd jobs inside the workshop — not ministries |
| **Minister** | Robin | Sets priority across domains; does not pretend to be a ministry |

**Routing picture:** signal arrives → M.O.I. classifies → ticket lands in a **ministry
domain** on M.O.T. → **Tuttle** (or a Bureau run for build work) does the work → outcome
recorded back to M.O.T. Ministries are the *in-trays*; workers are the *hands*.

**Visual rule:** THE HUB and M.O.T. UI show **ministry sigils / labels only** — department
geometry, enamel badges, routing-lane names. Character art belongs to **workers** (THE ENGINE,
workshop scenes, tarot). Never illustrate "Minister Plenty" as a person; illustrate Tuttle
carrying a Plenty docket.

**Lore rule:** The Bureau is the secret order of **workers** who actually
run the machine. The ministries are the solemn fiction on the org chart — Orwell's names,
Brazil's forms, TVA's corridors — with nobody home behind the desk except a domain label
and a pile of tickets waiting for Tuttle or the workshop.

---

## Structure

The system is a government. Each **ministry** owns a **domain** (no face — just a label and
queue). M.O.T. is the shared record layer underneath all of them. M.O.I. is the daily briefing
that pulls from all of them. **Tuttle** is the civil servant who does the work across ministries.
**Bureau specialists** do build work for Ministry of Flow. Robin is the Minister.

---

## The Core Ministries

### Ministry of Truth — M.O.T.
*"Who controls the past controls the future."*

The canonical record. Every issue, status update, and resolution across all domains lands
here as a ticket. The source of truth. Nothing is considered dealt with until M.O.T. says so.

- Ticket tracker: open / watching / snoozed / done
- Projects map 1:1 to domain ministries
- REST API for Tuttle to file and update tickets
- Web UI for Robin to triage, comment, and close
- The foundation everything else feeds into

**Build first.**

---

### Ministry of Information — M.O.I.
*"Ignorance is Strength."*

The intelligence layer. Monitors all domain ministries and produces the daily briefing.
Divided into two functions inherited from Sam Lowry's career:

- **Information Records** — passive intake. Monitors Gmail, server logs, Stripe, Sentry,
  school email, domain renewals. Classifies and files new items into M.O.T.
- **Information Retrieval** — active query. On-demand: "Tuttle, what's the status on AWS?"
  or "find everything about the ESIS invoice." Searches M.O.T. and connected sources.

Currently implemented as: the daily digest cloud routine (trig_019zRcnTemfALxvTb7ktbPh7).
Upgrade path: route new items into M.O.T. instead of Gmail drafts; add retrieval interface.

**Build second** (upgrade existing routine to file into M.O.T.).

---

## The Domain Ministries

These are the sources. They generate tickets that flow into M.O.T. and get surfaced by M.O.I.

---

### Ministry of Works
*Tuttle's home turf.*

Infrastructure and operations. The pipes, ducts, and wiring that everything runs on.

- AWS: Lightsail instances, S3, billing, Cost Explorer
- Server health: uptime, CPU/disk/memory, cert expiry, security groups
- Deploys: GitHub Actions, failed builds, migration errors
- Cron jobs and scheduled tasks

Signals: AWS billing emails, Sentry downtime alerts, GitHub deploy failures, CloudWatch.

---

### Ministry of Commerce
*Products and income.*

Everything that generates or could generate revenue.

- Nutrifax: support tickets, Stripe payments, Sentry errors, deploy status, bounces
- GrowOperative: app health, user activity, issues
- Upwork: job scanning (already live via rheo.ca), proposals, active contracts
- Stripe: failed charges, disputes, chargebacks, MRR

Signals: support@nutrifax.app, Stripe webhooks, GitHub deploy failures, rheo.ca Upwork triage.

---

### Ministry of Plenty
*Resources and obligations.*

Money in, money out. Everything that costs something or needs paying.

- Recurring bills: ESIS, Virgin Plus, Adobe, Vercel, Namecheap, AWS, MBNA
- Domain renewals: novadiem.com, cryptowatchtools.com, moonraccoon.org, rheo.ca, others
- Cash flow: Upwork income, Stripe MRR vs. burn rate
- Subscriptions: what's active, what's unused, what's about to renew

Signals: billing emails, Namecheap renewal notices, MBNA statement alerts, bank notifications.

---

### Ministry of Peace
*"War is Peace." Keeps things stable so nothing pages.*

Security and stability. The irony: unlike Orwell's version, this one actually maintains peace.

- Dependabot security alerts (rheos/platform, rheos/nutrifax, etc.)
- SSL cert expiry monitoring
- Security group / firewall anomalies
- Dependency audits
- Failed login / account alerts

Signals: GitHub security emails, Let's Encrypt expiry warnings, account alert emails.

---

### Ministry of Education
*Arowyn and CBESS.*

School admin for Arowyn Riversong, Crawford Bay Elementary Secondary School.

- School calendar: events, trips, deadlines
- Teacher and principal comms (Daryl-lee Schalm, Victoria McAllister)
- Absence notices, hot lunch, PAC meetings
- Co-parent coordination with Aisha

Signals: sysadmin@myeducation.gov.bc.ca, *@sd8.bc.ca, broadcasts@schoolmessengermail.com.

---

### Ministry of Flow
*The active pipeline. **aka Logistics.***

Projects in motion -- between idea and shipped. Not the ideas backlog, not finished products,
but the live work. What's being built right now, what's blocked, what needs a decision to move.

- Active builds: Oriva, M.O.T., GrowOperative features, new projects
- Experiments: spikes, prototypes, things being tested
- Blocked items: waiting on a key, a decision, a dependency, a co-founder
- Pipeline health: what's stalled, what's moving, what needs attention this week

**Logistics console:** local app at `~/Code/novadiem/society-desk` (npm `3010`) — read-only
dashboard for **Bureau framework runs** across installs (`state.json`, `log.md`, cast rail,
workflows view). This is the Ministry of Flow instrument panel; repo slug `society-desk` until
renamed. Not M.O.T. tickets; not fleet ops.

Connects to M.O.T. -- a blocked pipeline item becomes a ticket.
Connects to Commerce -- when something ships, it graduates out of Flow.

---

### Ministry of the Interior
*Personal admin and planning.*

Life decisions, logistics, and the things that don't fit anywhere else.

- Kaslo move: logistics, timing, downsizing
- International planning: Thailand, Ecuador research
- DUNS / Novadiem registry items
- Health and personal admin
- Ideas and deferred decisions

Signals: Robin's own notes, reminders, deferred items from other ministries.

---

### Ministry of Foreign Affairs
*External relationships and third-party dependencies.*

Vendors, registrars, and services Robin depends on but doesn't control.

- Namecheap: domain status, billing
- Google: OAuth, Search Console, Ads
- Apple: developer account, DUNS status
- Anthropic: Claude subscription, API usage
- OpenRouter, Resend, Vercel: service health and billing

Signals: vendor emails, renewal notices, API status pages.

---

## The Government at a Glance

```
                    ┌─────────────────┐
                    │     TUTTLE      │
                    │  (civil servant) │
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │    Ministry of Information   │
              │           M.O.I.            │
              │  Records │ Retrieval        │
              └──────────────┬──────────────┘
                             │ files into
              ┌──────────────▼──────────────┐
              │     Ministry of Truth        │
              │           M.O.T.            │
              │     (ticket tracker)         │
              └──────────────┬──────────────┘
                             │ tickets sourced from
        ┌────────┬────────┬────────┬────────┬────────┐
        │        │        │        │        │        │
      Works  Commerce  Plenty   Peace  Education  Flow
        │        │        │        │        │        │
   Interior  Foreign
              Affairs
```

---

## Build Order

1. **M.O.T.** -- the ticket tracker on OpenClaw-1. Foundation for everything.
2. **M.O.I. upgrade** -- route daily digest into M.O.T. instead of Gmail drafts.
3. **Ministry of Works** -- infra health digest wired into M.O.T.
4. **Ministry of Commerce** -- Nutrifax + Upwork alerts into M.O.T.
5. **Ministry of Plenty** -- finance/billing sweep into M.O.T.
6. Others as the system proves its value.

---

## Technical Notes

- **Domain**: `mot.novadiem.com` for M.O.T. (the app). M.O.I. stays as a cloud routine.
- **Stack**: Next.js + SQLite on OpenClaw-1. Apache vhost + Let's Encrypt cert.
- **Auth**: simple — just Robin for now.
- **API**: REST, API key auth so cloud routines can POST tickets without UI.
- **Telegram**: delivery target for M.O.I. briefings once M.O.T. is live.
- **Mission Control**: to be removed from OpenClaw-1 before M.O.T. deploys.
