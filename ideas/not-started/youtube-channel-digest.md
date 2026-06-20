# YouTube Channel Digest — grouped channel monitoring → AI digest → Telegram

Date: 2026-06-17
Status: not started

**Canonical spec:** `~/Code/novadiem/rheo.ca/docs/youtube-channel-digest.md` (full architecture,
flow, prompts, file layout, implementation steps). This file is the **roadmap entry** — where the
idea sits, what it depends on, and how it relates to the M.O.I. spine. Don't duplicate the spec
here; edit it there and keep this entry pointing at it.

---

## One-liner

Poll YouTube channels (grouped by purpose) via RSS twice a day, fetch each new video's transcript,
run a per-group `claude -p` prompt over it, and deliver a grouped Telegram digest. Runs on the
rheo.ca box under `/opt/mot/bot/youtube-digest/`.

## Why

Robin already has a proven prompt that extracts actionable crypto-perp trading setups (Blofin) from
Chart Hackers transcripts into a master setup table. The idea generalizes that: any channel group
gets its own analysis prompt (trading setups, plain summary, …), so monitoring a channel becomes
"add an entry to `channels.json` + optionally a prompt file." No YouTube Data API key — RSS covers
the latest 15 videos per channel, enough for 2×/day polling.

## The relationship that puts it on *this* roadmap — a future M.O.I. adapter

The spec says it twice: this "will eventually tie into the M.O.T. ministries system as a data feed"
and "M.O.T. ticket creation per video (tie into ministries)." That makes it a **future M.O.I.
ingestion adapter** — a YouTube-channel `source` whose per-group prompt is the classifier, that
later files M.O.T. tickets instead of (or alongside) a Telegram digest. It plugs straight into the
spine being reconciled in run `20260617-moi-spine-reconcile`, whose whole design goal is "add a
source = add validated config + one MCP call path." So:

- **Phase 1 (standalone, ships first):** RSS → transcript → `claude -p` → Telegram digest. Zero
  M.O.T. dependency. Independently useful (the trading digest earns its keep on day one).
- **Phase 2 (the tie-in):** the digest runner files tickets, becoming a `youtube` adapter under the
  M.O.I. spine — `ministry`, `classifierInput`, `sourceRefRule` (video id), `expectedFrequency`.
  **Filing interface is the spine's choice, not pinned here:** the runner lives on rheo.ca and is NOT
  egress-blocked, so local REST is open to it as well as MCP — the `20260617-moi-spine-reconcile` run
  settles which interface on-box adapters use (note 6 below). Best done *after* the spine lands so it
  inherits the audit / dedup / heartbeat machinery rather than reinventing it.

This is also a useful **second adapter** to validate the spine's "one adapter = config" claim — the
Gmail re-route (Phase-2 of the spine) proves the pattern; a YouTube source is the first real test
that a *different* channel type drops in as config.

## Key dependency / blocker

**YouTube blocks datacenter IPs** — the rheo.ca server can't reliably fetch transcripts. The spec's
planned fix is a **home-relay script** on Robin's residential connection that fetches transcripts and
POSTs them to a server endpoint (`POST /api/youtube-digest/transcripts`) the runner reads. Until that
relay exists, transcripts must be supplied manually. This relay is the real first build task — the
RSS/analysis/Telegram half is straightforward; the transcript path is the risk.

## First-launch set (explicit)

To stop the build prompt from guessing (the index and the canonical spec differed): **first launch =
the one `trading` group from the canonical spec's `channels.json` — Chart Hackers, MooninPapa, and
100x Club — using the `trading_setups` prompt.** Chart Hackers is the channel the proven prompt was
written against; the other two ride the same analysis type. No other groups at launch; Robin adds more
channels/groups over time (the structure supports it).

## Oversight notes — carry forward before any build run

Robin's review flagged these; fold each into the spec / build prompt before a build run is scoped.

1. **Home-relay needs a real contract, not just "POST transcripts."** Specify: auth on the public
   relay endpoint; how the relay learns the pending list (a server pull-list endpoint vs. a manual
   drop format); where transcripts are cached on the server; **idempotency keyed by `video_id`**;
   retry behaviour; and what happens when the relay posts a stale or duplicate transcript.
2. **No lost videos on partial failure.** A video is marked delivered ONLY after transcript fetch +
   Claude analysis + Telegram send all succeed. If Claude analysis or the Telegram send fails, the
   video stays **retryable** — add retry / dead-letter handling for analysis-and-send failures, not
   only the transcript-unavailable `attempts` counter the spec already has.
3. **Treat transcripts as untrusted model input.** The prompt must fence the transcript text clearly,
   ignore any instructions embedded inside the transcript (prompt-injection), and keep the **"analysis
   only / no auto-trading action"** guardrail around trading setups. Add timeout + context-size
   handling for long transcripts before the `claude -p` call (truncate/chunk; don't blow the window).
4. **External-action / production gates apply.** Live Telegram sends, cron installation, and exposing
   the relay endpoint are externally visible / production-ish. A build run **stops for the appropriate
   checkpoint** (external-action and/or production boundary) before any of those is turned on — they
   are not self-authorizing.
5. **First-launch set** — made explicit in the section above.
6. **Don't over-spec the M.O.I. filing interface yet.** The runner lives on rheo.ca and is NOT
   egress-blocked, so it can file via **local REST or MCP** — say "files via the spine's chosen on-box
   filing interface" and let the `20260617-moi-spine-reconcile` run settle which interface on-box
   adapters use. Don't hard-wire MCP.

## Sequencing

- **Not blocking, and not blocked by, the M.O.I. spine reconcile** — Phase 1 stands alone.
- Natural order: build the home-relay + Phase-1 digest as its own small run (it's a `feature` or a
  scoped build, mostly the relay + `run.js` + cron); fold in the M.O.I. ticket-filing tie-in once the
  spine (`20260617-moi-spine-reconcile`) is built, so it lands as a validated adapter.
- Lives on the rheo.ca box alongside the M.O.T. app + Rheo bot (additive); uses the bot's existing
  Telegram sender and `claude -p` CLI already on the server.
