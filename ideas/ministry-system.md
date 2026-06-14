# The Ministry System

A personal intelligence and operations government for Robin Goodwin, staffed by Tuttle.
Inspired by Orwell's 1984 and Gilliam's Brazil.

---

## Structure

The system is a government. Each ministry owns a domain. M.O.T. is the shared record
layer underneath all of them. M.O.I. is the daily briefing that pulls from all of them.
Tuttle is the civil servant that staffs every ministry. Robin is the Minister.

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
        ┌──────────┬─────────┼──────────┬──────────┐
        │          │         │          │          │
      Works   Commerce    Plenty      Peace    Education
        │          │         │          │          │
   Interior   Foreign
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
