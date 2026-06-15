# Upwork triage without API access

Idea note for reviving Robin's existing Upwork triage project without waiting on an Upwork API key.

## Existing project

Local project:

- `/Users/robin/Code/novadiem/rheo.ca`
- Backend: FastAPI at `backend/app/`
- Frontend: Vite/React at `frontend/`
- Live API: `https://api.rheo.ca`
- Intended UI path: `https://rheo.ca/upwork/`

Current state observed 2026-06-15:

- `https://api.rheo.ca/health` is alive.
- `https://api.rheo.ca/jobs/` returns mock job data.
- `/jobs/fetch-mock` is the only ingestion endpoint.
- `backend/app/routers/auth.py` is an Upwork OAuth stub.
- `backend/app/services/upwork.py` parses expected Upwork GraphQL shapes, but does not fetch real jobs.
- `https://rheo.ca/upwork/` serves a "coming soon" placeholder, not the React triage UI.
- The React app currently calls `/api`; `https://rheo.ca/api/health` returns 404, so production needs either
  a same-origin `/api` proxy or a frontend config that points at `https://api.rheo.ca`.

## Problem

The original plan depended on Upwork API/OAuth access. Upwork did not grant an API key before
Robin had more platform history, creating a chicken-and-egg block.

Waiting for API access stalls the sales system. Scraping or auto-applying would create platform
risk. The better move is to keep Upwork interactions human-approved and build the agentic tooling
around job alerts, saved searches, and manual review.

## New direction

Turn the project into an **Upwork Sales Desk**:

1. Robin creates saved searches and alert emails inside Upwork.
2. The tool ingests job-alert emails, pasted job URLs, or pasted job descriptions.
3. The backend normalizes each job into the existing `Job` model or a small source-agnostic extension.
4. Existing Tier 1 / Tier 2 scoring ranks fit.
5. The UI shows ranked jobs, risks, why-fit notes, and proposal drafts.
6. Robin manually reviews and submits proposals through Upwork.

No auto-submit. No unauthorized scraping. No outbound outside Upwork unless the platform/client
allows it.

## Candidate ingestion sources

Start with the lowest-risk sources:

- **Manual paste:** paste URL/title/description/budget/client details into a small form.
- **Email alert parser:** parse Upwork job-alert emails that Robin already receives.
- **Browser share/bookmarklet later:** send the current job page's visible text to the local app.
- **CSV import later:** import a manually exported or assistant-curated job list.

Avoid:

- automated Upwork scraping
- automated proposal submission
- bypassing Upwork messaging/payment rules
- storing credentials that impersonate a browser session

## MVP shape

Backend:

- Add `POST /jobs/manual` for pasted jobs.
- Add optional `source` fields: `source_type`, `source_url`, `raw_payload`, `source_received_at`.
- Add `POST /jobs/ingest-email` that accepts raw email text and extracts job cards.
- Reuse `run_tier1`, `score_job`, and `generate_proposal`.
- Keep `fetch-mock` for demos/tests.

Frontend:

- Replace "Fetch Mock Jobs" as the primary action with "Add Job" / "Paste Alert".
- Keep job cards, dismiss, show more, draft proposal, and LLM logs.
- Add status labels: `new`, `review`, `submitted`, `reply`, `won`, `lost`, `dismissed`.
- Add a field for manual notes and proposal-submitted date.

Deployment:

- Deploy the built React UI to `/upwork/`.
- Fix production API routing, either with an Apache `/api` proxy on `rheo.ca` or by configuring the
  frontend to call `https://api.rheo.ca`.
- Keep public access in mind. This is a private sales tool, so add auth before putting real job data
  or proposal drafts behind the route.

## Daily operating workflow

1. Assistant checks Upwork saved-search emails or Robin pastes promising jobs.
2. Tool imports jobs into the queue.
3. Tier 1 filters obvious bad fits.
4. Tier 2 scores fit and gives one-line reasoning.
5. Assistant prepares drafts only for high-fit jobs.
6. Robin reviews, edits, and manually submits 3-5 proposals per day.
7. Robin or assistant updates status in the dashboard.
8. Weekly review adjusts searches, scoring rules, and proposal patterns.

## Scoring adjustments

Favor:

- small first-win jobs
- clear scope
- payment verified
- recent posts
- low proposal count
- client has hiring history, or a very specific high-quality new-client post
- Python/FastAPI, Rails, React, Stripe, LLM/API integration, data/report automation, workflow fixes

Penalize:

- vague "AI agent" hype without workflow detail
- low budget or unrealistic timeline
- 50+ proposals
- off-platform contact requests
- jobs requiring platform/deep-domain expertise Robin does not have
- anything that smells like unpaid product discovery disguised as a fixed bid

## Framework tie-in

This could become a lightweight Bureau workflow later:

- **Workflow name:** `sales-desk`
- **When to use:** find, rank, and draft responses to paid-work opportunities without auto-sending.
- **Agents:** Analyst-style source parser, Challenger-style risk reviewer, Counselor for proposal voice.
- **Hard gate:** no proposal, email, or platform message is sent without explicit human action.

It also fits the broader "Ministry of Commerce" idea: Upwork alerts, LinkedIn leads, and small-business
outbound opportunities become one reviewed income queue rather than scattered browser tabs.

## First implementation pass

1. Add manual job ingestion.
2. Deploy the actual React UI at `/upwork/`.
3. Fix API routing.
4. Add status tracking.
5. Add email-alert parsing.
6. Add private auth.
7. Add weekly metrics: reviewed, drafted, submitted, replies, wins, losses.

## Success criteria

- Robin can add a job without Upwork API access.
- The dashboard ranks it and explains the score.
- The system drafts a proposal but never submits it.
- Robin can track submitted proposals and outcomes.
- After 2-4 weeks, the tool has enough history to improve saved searches and proposal style.
- Once Robin has Upwork history, API access can be requested again as an enhancement, not a blocker.
